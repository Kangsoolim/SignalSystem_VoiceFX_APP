function [yFrame, state] = applyVocalFX(xFrame, fs, fxConfig, state)
%APPLYVOCALFX Apply lightweight vocal/device/digital effects.
%   Supported modes are none, telephone, walkie_talkie, radio, lofi,
%   bitcrusher, and robot. The implementation stays causal and frame-safe.

if nargin < 3 || isempty(fxConfig)
    fxConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
fxConfig = fillFxDefaults(fxConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'fx') || isempty(state.fx)
    state.fx = struct();
end

yFrame = double(xFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;

if ~isfield(fxConfig, 'enabled') || ~fxConfig.enabled
    return;
end

fxType = getFxType(fxConfig);
if strcmpi(fxType, 'none') || isempty(yFrame)
    return;
end

dry = yFrame;
mix = clamp01(getFieldOrDefault(fxConfig, 'mix', 1.0));
intensity = clamp01(getFieldOrDefault(fxConfig, 'intensity', 0.6));

if ~isfield(state.fx, 'sampleIndex')
    state.fx.sampleIndex = 0;
end

switch lower(fxType)
    case 'telephone'
        [wet, state] = filterTone(dry, fs, 300, 3400, 'bandpass', 4, fxType, state);
        wet = softDrive(wet, 1.0 + 0.7 * intensity);

    case 'walkie_talkie'
        [wet, state] = filterTone(dry, fs, 400, 2800, 'bandpass', 4, fxType, state);
        wet = softDrive(wet, getFieldOrDefault(fxConfig, 'drive', 1.8) + intensity);
        if ~isempty(fs) && isfinite(fs) && fs > 0
            n = (0:numel(wet)-1).' + state.fx.sampleIndex;
            wet = wet + 0.015 * intensity * sin(2 * pi * min(3800, 0.42 * fs) * n / fs);
        end

    case 'radio'
        [wet, state] = filterTone(dry, fs, 120, 5000, 'bandpass', 3, fxType, state);
        wet = softDrive(wet, 1.0 + 0.35 * intensity);
        wet = 0.9 * wet;

    case 'lofi'
        [wet, state] = filterTone(dry, fs, [], 3200, 'lowpass', 3, fxType, state);
        [wet, state] = sampleHold(wet, fxConfig, state);
        wet = quantizeSignal(wet, max(5, round(10 - 4 * intensity)));

    case 'bitcrusher'
        bitDepth = getFieldOrDefault(fxConfig, 'bitDepth', 8);
        bitDepth = round(max(3, min(16, double(bitDepth) - round(4 * intensity))));
        wet = quantizeSignal(dry, bitDepth);

    case 'robot'
        wet = robotModulate(dry, fs, fxConfig, state);

    otherwise
        wet = dry;
end

yFrame = (1 - mix) * dry + mix * wet;
yFrame = cleanColumn(yFrame);
yFrame = limitInternal(yFrame);
state.fx.sampleIndex = state.fx.sampleIndex + numel(yFrame);
state.fx.lastMode = fxType;
state.fx.lastFs = fs;
end

function config = fillFxDefaults(config)
defaults = makeDefaultConfig();
defaultConfig = defaults.fx;
fields = fieldnames(defaultConfig);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name)
        config.(name) = defaultConfig.(name);
    end
end
end

function fxType = getFxType(config)
if isfield(config, 'type') && ~isempty(config.type)
    fxType = char(config.type);
elseif isfield(config, 'mode') && ~isempty(config.mode)
    fxType = char(config.mode);
else
    fxType = 'none';
end
end

function [wet, state] = filterTone(x, fs, lowCutoff, highCutoff, filterKind, order, modeName, state)
wet = x;
if isempty(fs) || ~isfinite(fs) || fs <= 0
    return;
end

[b, a, signature] = designToneFilter(fs, lowCutoff, highCutoff, filterKind, order, modeName);
ziLength = max(numel(a), numel(b)) - 1;
if ziLength > 0
    if ~isfield(state.fx, 'filterSignature') || ~strcmp(state.fx.filterSignature, signature) || ...
            ~isfield(state.fx, 'filterZi') || numel(state.fx.filterZi) ~= ziLength
        zi = zeros(ziLength, 1);
    else
        zi = state.fx.filterZi;
    end
    [wet, state.fx.filterZi] = filter(b, a, x, zi);
else
    wet = filter(b, a, x);
    state.fx.filterZi = [];
end
state.fx.filterSignature = signature;
end

function [b, a, signature] = designToneFilter(fs, lowCutoff, highCutoff, filterKind, order, modeName)
nyquist = fs / 2;
order = max(1, min(8, round(order)));
switch lower(filterKind)
    case 'lowpass'
        highCutoff = clampFrequency(highCutoff, nyquist, min(3200, 0.40 * fs));
        normalized = highCutoff / nyquist;
        if exist('butter', 'file') == 2
            [b, a] = butter(order, normalized, 'low');
        else
            alpha = exp(-2 * pi * highCutoff / fs);
            b = 1 - alpha;
            a = [1, -alpha];
        end
    otherwise
        lowCutoff = clampFrequency(lowCutoff, nyquist, 300);
        highCutoff = clampFrequency(highCutoff, nyquist, min(3400, 0.42 * fs));
        if highCutoff <= lowCutoff
            highCutoff = min(nyquist * 0.95, lowCutoff + 100);
        end
        if exist('butter', 'file') == 2
            [b, a] = butter(order, [lowCutoff, highCutoff] / nyquist, 'bandpass');
        else
            b = 1;
            a = 1;
        end
end
signature = sprintf('%s_%s_fs%.9g_lo%.9g_hi%.9g_o%d', lower(modeName), lower(filterKind), fs, ...
    emptyToZero(lowCutoff), emptyToZero(highCutoff), order);
end

function [y, state] = sampleHold(x, config, state)
intensity = clamp01(getFieldOrDefault(config, 'intensity', 0.6));
holdSamples = max(1, round(1 + 8 * intensity));
if ~isfield(state.fx, 'holdValue') || ~isfield(state.fx, 'holdRemaining')
    state.fx.holdValue = 0;
    state.fx.holdRemaining = 0;
end

y = zeros(size(x));
for n = 1:numel(x)
    if state.fx.holdRemaining <= 0
        state.fx.holdValue = x(n);
        state.fx.holdRemaining = holdSamples;
    end
    y(n) = state.fx.holdValue;
    state.fx.holdRemaining = state.fx.holdRemaining - 1;
end
end

function y = quantizeSignal(x, bitDepth)
bitDepth = max(2, min(16, round(bitDepth)));
levels = 2 ^ bitDepth;
scale = max(1, levels / 2 - 1);
y = round(cleanColumn(x) * scale) / scale;
end

function y = robotModulate(x, fs, config, state)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
modFreq = abs(double(getFieldOrDefault(config, 'modFreq', 35)));
if isempty(modFreq) || ~isfinite(modFreq) || modFreq <= 0
    modFreq = 35;
end
modFreq = min(modFreq, fs * 0.25);
intensity = clamp01(getFieldOrDefault(config, 'intensity', 0.6));
n = (0:numel(x)-1).' + state.fx.sampleIndex;
carrier = cos(2 * pi * modFreq * n / fs);
y = x .* ((1 - 0.5 * intensity) + intensity * carrier);
end

function y = softDrive(x, drive)
drive = max(0.1, double(drive));
y = tanh(drive * x) / tanh(drive);
end

function value = clampFrequency(value, nyquist, defaultValue)
if isempty(value) || ~isfinite(double(value)) || double(value) <= 0
    value = defaultValue;
end
value = min(max(abs(double(value)), 1), nyquist * 0.95);
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

function x = cleanColumn(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end

function y = limitInternal(x)
y = min(max(x, -1), 1);
end

function value = emptyToZero(value)
if isempty(value)
    value = 0;
end
end
