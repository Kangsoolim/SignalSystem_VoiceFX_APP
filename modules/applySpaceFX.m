function [yFrame, state] = applySpaceFX(xFrame, fs, spaceConfig, state)
%APPLYSPACEFX Apply lightweight delay and environment-style space effects.
%   Supported modes are none, delay, reverb, bathroom, cave, and stage.
%   Effects use causal buffers stored in state.space for frame continuity.

if nargin < 3 || isempty(spaceConfig)
    spaceConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
spaceConfig = fillSpaceDefaults(spaceConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'space') || isempty(state.space)
    state.space = struct();
end

yFrame = double(xFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;

if ~isfield(spaceConfig, 'enabled') || ~spaceConfig.enabled
    return;
end

spaceType = getSpaceType(spaceConfig);
if strcmpi(spaceType, 'none') || isempty(yFrame)
    return;
end

if isempty(fs) || ~isfinite(fs) || fs <= 0
    yFrame(~isfinite(yFrame)) = 0;
    return;
end

dry = yFrame;
mix = clamp01(getFieldOrDefault(spaceConfig, 'mix', 0.35));
feedback = clampFeedback(getFieldOrDefault(spaceConfig, 'feedback', 0.35));
reverbAmount = clamp01(getFieldOrDefault(spaceConfig, 'reverbAmount', 0.4));

switch lower(spaceType)
    case 'delay'
        delayTime = getFieldOrDefault(spaceConfig, 'delayTime', 0.25);
        delaySamples = timeToSamples(delayTime, fs, 0.25);
        [wet, state] = processDelay(dry, delaySamples, feedback, spaceType, state);

    case 'reverb'
        delayTimes = [0.029, 0.037, 0.043, 0.053];
        gains = reverbAmount * [0.55, 0.42, 0.32, 0.24];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, feedback * 0.7, spaceType, state);

    case 'bathroom'
        delayTimes = [0.010, 0.017, 0.024, 0.031];
        gains = max(reverbAmount, 0.55) * [0.70, 0.52, 0.38, 0.25];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, min(0.45, feedback + 0.05), spaceType, state);

    case 'cave'
        delayTimes = [0.080, 0.135, 0.210, 0.310];
        gains = max(reverbAmount, 0.65) * [0.75, 0.58, 0.42, 0.30];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, min(0.75, feedback + 0.20), spaceType, state);

    case 'stage'
        delayTimes = [0.035, 0.055, 0.083, 0.115];
        gains = max(reverbAmount, 0.45) * [0.60, 0.48, 0.35, 0.22];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, min(0.55, feedback + 0.05), spaceType, state);

    otherwise
        wet = dry;
end

yFrame = (1 - mix) * dry + mix * wet;
yFrame = cleanColumn(yFrame);
yFrame = limitInternal(yFrame);
state.space.lastMode = spaceType;
state.space.lastFs = fs;
end

function config = fillSpaceDefaults(config)
defaults = makeDefaultConfig();
defaultConfig = defaults.space;
fields = fieldnames(defaultConfig);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name)
        config.(name) = defaultConfig.(name);
    end
end
end

function spaceType = getSpaceType(config)
if isfield(config, 'type') && ~isempty(config.type)
    spaceType = char(config.type);
elseif isfield(config, 'mode') && ~isempty(config.mode)
    spaceType = char(config.mode);
else
    spaceType = 'none';
end
end

function [wet, state] = processDelay(x, delaySamples, feedback, modeName, state)
signature = sprintf('%s_d%d_fb%.6f', lower(modeName), delaySamples, feedback);
if ~isfield(state.space, 'delaySignature') || ~strcmp(state.space.delaySignature, signature) || ...
        ~isfield(state.space, 'delayBuffer') || numel(state.space.delayBuffer) ~= delaySamples
    state.space.delayBuffer = zeros(delaySamples, 1);
    state.space.delayIndex = 1;
    state.space.delaySignature = signature;
end

wet = zeros(size(x));
buffer = state.space.delayBuffer;
idx = state.space.delayIndex;
for n = 1:numel(x)
    delayed = buffer(idx);
    wet(n) = x(n) + feedback * delayed;
    buffer(idx) = x(n) + feedback * delayed;
    idx = idx + 1;
    if idx > delaySamples
        idx = 1;
    end
end
state.space.delayBuffer = buffer;
state.space.delayIndex = idx;
end

function [wet, state] = processMultiDelay(x, fs, delayTimes, gains, feedback, modeName, state)
delaySamples = arrayfun(@(v) timeToSamples(v, fs, v), delayTimes);
signature = sprintf('%s_%s_g%s_fb%.6f', lower(modeName), mat2str(delaySamples), mat2str(gains, 4), feedback);
if ~isfield(state.space, 'reverbSignature') || ~strcmp(state.space.reverbSignature, signature) || ...
        ~isfield(state.space, 'reverbBuffers') || numel(state.space.reverbBuffers) ~= numel(delaySamples)
    state.space.reverbBuffers = cell(numel(delaySamples), 1);
    state.space.reverbIndices = ones(numel(delaySamples), 1);
    for k = 1:numel(delaySamples)
        state.space.reverbBuffers{k} = zeros(delaySamples(k), 1);
    end
    state.space.reverbSignature = signature;
end

wet = zeros(size(x));
buffers = state.space.reverbBuffers;
indices = state.space.reverbIndices;
normalizer = 1 + sum(abs(gains));

for n = 1:numel(x)
    acc = x(n);
    for k = 1:numel(delaySamples)
        idx = indices(k);
        delayed = buffers{k}(idx);
        acc = acc + gains(k) * delayed;
        buffers{k}(idx) = x(n) + feedback * delayed;
        idx = idx + 1;
        if idx > delaySamples(k)
            idx = 1;
        end
        indices(k) = idx;
    end
    wet(n) = acc / normalizer;
end

state.space.reverbBuffers = buffers;
state.space.reverbIndices = indices;
end

function samples = timeToSamples(timeSeconds, fs, defaultSeconds)
if isempty(timeSeconds) || ~isfinite(double(timeSeconds)) || double(timeSeconds) <= 0
    timeSeconds = defaultSeconds;
end
samples = round(abs(double(timeSeconds)) * fs);
samples = max(1, min(samples, max(1, round(2 * fs))));
end

function value = getFieldOrDefault(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function value = clamp01(value)
value = min(max(double(value), 0), 1);
end

function value = clampFeedback(value)
value = min(max(double(value), 0), 0.85);
end

function x = cleanColumn(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end

function y = limitInternal(x)
y = min(max(x, -1), 1);
end
