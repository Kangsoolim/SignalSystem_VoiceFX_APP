function [yFrame, state] = applySpaceFX(xFrame, fs, spaceConfig, state)
%APPLYSPACEFX Apply lightweight delay and environment-style space effects.
%   Supported modes are none, delay, bathroom, and cave. stage is a legacy alias for bathroom.
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

yFrame = cleanColumn(xFrame);

if ~isfield(spaceConfig, 'enabled') || ~spaceConfig.enabled
    return;
end

spaceType = getSpaceType(spaceConfig);
if strcmpi(spaceType, 'none') || isempty(yFrame)
    return;
end

if isempty(fs) || ~isfinite(fs) || fs <= 0
    return;
end

dry = yFrame;
spaceParams = resolveSpaceParams(spaceType, spaceConfig);
mix = clamp01(getFieldOrDefault(spaceParams, 'mix', 0.28));
feedback = clampFeedback(getFieldOrDefault(spaceParams, 'feedback', 0.24));
reverbAmount = clamp01(getFieldOrDefault(spaceParams, 'reverbAmount', 0.30));
damping = clamp01(getFieldOrDefault(spaceParams, 'damping', 0.16));
wetGain = clampGain(getFieldOrDefault(spaceParams, 'wetGain', 1.0));

switch lower(spaceType)
    case 'delay'
        delayTime = getFieldOrDefault(spaceParams, 'delayTime', 0.18);
        delaySamples = timeToSamples(delayTime, fs, 0.18);
        delayGain = clamp01(getFieldOrDefault(spaceParams, 'delayGain', 0.58));
        [wet, state] = processDelay(dry, delaySamples, feedback, delayGain, spaceType, state);


    case 'bathroom'
        delayTimes = [0.018, 0.035, 0.061, 0.095, 0.145];
        gains = reverbAmount * [0.75, 0.62, 0.48, 0.35, 0.24];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, feedback * 0.75, damping, wetGain, spaceType, state);

    case 'cave'
        delayTimes = [0.070, 0.118, 0.182, 0.265, 0.360];
        gains = reverbAmount * [0.72, 0.54, 0.38, 0.24, 0.14];
        [wet, state] = processMultiDelay(dry, fs, delayTimes, gains, min(0.44, feedback), damping, wetGain, spaceType, state);


    otherwise
        wet = dry;
end

yFrame = dry + mix * (wet - dry);
yFrame = cleanColumn(yFrame);
yFrame = limitInternal(yFrame);
state.space.lastMode = spaceType;
state.space.lastFs = fs;
state.space.lastMix = mix;
state.space.lastFeedback = feedback;
state.space.lastReverbAmount = reverbAmount;
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

function params = resolveSpaceParams(spaceType, config)
defaults = makeDefaultConfig();
defaultSpace = defaults.space;
params = struct();
modeKey = matlab.lang.makeValidName(lower(char(spaceType)));

if isfield(defaultSpace, 'presets') && isfield(defaultSpace.presets, modeKey)
    params = defaultSpace.presets.(modeKey);
end

% Top-level legacy controls override presets only when intentionally changed
% from framework defaults. config.params always wins below.
genericFields = {'mix', 'delayTime', 'feedback', 'reverbAmount'};
for k = 1:numel(genericFields)
    name = genericFields{k};
    if isfield(config, name) && ~isempty(config.(name))
        if ~isfield(params, name) || ~valuesEqual(config.(name), defaultSpace.(name))
            params.(name) = config.(name);
        end
    end
end

skipFields = {'enabled', 'type', 'mode', 'params', 'presetOrder', 'displayPresets', 'hiddenPresets', 'presets'};
configFields = fieldnames(config);
for k = 1:numel(configFields)
    name = configFields{k};
    if any(strcmp(name, skipFields)) || any(strcmp(name, genericFields))
        continue;
    end
    if ~isempty(config.(name))
        params.(name) = config.(name);
    end
end

if isfield(config, 'params') && isstruct(config.params)
    params = mergeStruct(params, config.params);
end
end

function merged = mergeStruct(base, overrides)
merged = base;
names = fieldnames(overrides);
for k = 1:numel(names)
    merged.(names{k}) = overrides.(names{k});
end
end

function tf = valuesEqual(a, b)
try
    tf = isequaln(a, b);
catch
    tf = isequal(a, b);
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
if strcmpi(spaceType, 'stage')
    spaceType = 'bathroom';
end
end

function [wet, state] = processDelay(x, delaySamples, feedback, delayGain, modeName, state)
signature = sprintf('%s_d%d_fb%.6f_g%.6f', lower(modeName), delaySamples, feedback, delayGain);
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
    wet(n) = x(n) + delayGain * delayed;
    buffer(idx) = limitInternal(x(n) + feedback * delayed);
    idx = idx + 1;
    if idx > delaySamples
        idx = 1;
    end
end
state.space.delayBuffer = buffer;
state.space.delayIndex = idx;
end

function [wet, state] = processMultiDelay(x, fs, delayTimes, gains, feedback, damping, wetGain, modeName, state)
delaySamples = arrayfun(@(v) timeToSamples(v, fs, v), delayTimes);
signature = sprintf('%s_%s_g%s_fb%.6f_dp%.6f_wg%.6f', lower(modeName), mat2str(delaySamples), mat2str(gains, 4), feedback, damping, wetGain);
if ~isfield(state.space, 'reverbSignature') || ~strcmp(state.space.reverbSignature, signature) || ...
        ~isfield(state.space, 'reverbBuffers') || numel(state.space.reverbBuffers) ~= numel(delaySamples)
    state.space.reverbBuffers = cell(numel(delaySamples), 1);
    state.space.reverbIndices = ones(numel(delaySamples), 1);
    state.space.reverbDampStates = zeros(numel(delaySamples), 1);
    for k = 1:numel(delaySamples)
        state.space.reverbBuffers{k} = zeros(delaySamples(k), 1);
    end
    state.space.reverbSignature = signature;
elseif ~isfield(state.space, 'reverbDampStates') || numel(state.space.reverbDampStates) ~= numel(delaySamples)
    state.space.reverbDampStates = zeros(numel(delaySamples), 1);
end

wet = zeros(size(x));
buffers = state.space.reverbBuffers;
indices = state.space.reverbIndices;
dampStates = state.space.reverbDampStates;
normalizer = max(1, 0.68 * sum(abs(gains)));

for n = 1:numel(x)
    wetDelta = 0;
    for k = 1:numel(delaySamples)
        idx = indices(k);
        delayedRaw = buffers{k}(idx);
        delayed = (1 - damping) * delayedRaw + damping * dampStates(k);
        dampStates(k) = delayed;
        wetDelta = wetDelta + gains(k) * delayed;
        buffers{k}(idx) = limitInternal(x(n) + feedback * delayed);
        idx = idx + 1;
        if idx > delaySamples(k)
            idx = 1;
        end
        indices(k) = idx;
    end
    wet(n) = x(n) + wetGain * wetDelta / normalizer;
end

state.space.reverbBuffers = buffers;
state.space.reverbIndices = indices;
state.space.reverbDampStates = dampStates;
end

function samples = timeToSamples(timeSeconds, fs, defaultSeconds)
if isempty(timeSeconds) || ~isfinite(double(timeSeconds)) || double(timeSeconds) <= 0
    timeSeconds = defaultSeconds;
end
samples = round(abs(double(timeSeconds)) * fs);
samples = max(1, min(samples, max(1, round(1.5 * fs))));
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
value = min(max(double(value), 0), 0.70);
end

function value = clampGain(value)
value = min(max(double(value), 0), 2.5);
end

function x = cleanColumn(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end

function y = limitInternal(x)
y = min(max(x, -1), 1);
end
