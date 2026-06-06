function [yFrame, state] = applyVoiceStyle(xFrame, fs, voiceConfig, state)
%APPLYVOICESTYLE Apply lightweight traditional voice style presets.
%   These modes are explainable approximations, not AI voice conversion.
%   Pitch shifting uses shiftPitch when available and falls back to EQ-style
%   shaping so frame processing remains stable.

if nargin < 3 || isempty(voiceConfig)
    voiceConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
voiceConfig = fillVoiceDefaults(voiceConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'voice') || isempty(state.voice)
    state.voice = struct();
end

yFrame = double(xFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;

if ~isfield(voiceConfig, 'enabled') || ~voiceConfig.enabled
    return;
end

voiceType = getVoiceType(voiceConfig);
if strcmpi(voiceType, 'none') || isempty(yFrame)
    return;
end

dry = yFrame;
mix = clamp01(getFieldOrDefault(voiceConfig, 'mix', 1.0));
intensity = clamp01(getFieldOrDefault(voiceConfig, 'intensity', 0.6));

if ~isfield(state.voice, 'sampleIndex')
    state.voice.sampleIndex = 0;
end
if ~isfield(state.voice, 'styleSignature') || ~strcmp(state.voice.styleSignature, voiceType)
    state.voice.eqLowPrev = 0;
    state.voice.eqPresencePrev = 0;
    state.voice.styleSignature = voiceType;
end

switch lower(voiceType)
    case 'male'
        semitones = getStylePitch(voiceConfig, -3.0 * intensity);
        wet = tryPitchShift(dry, semitones);
        [wet, state] = toneShape(wet, fs, state, 0.28 + intensity * 0.32, -0.18 - 0.18 * intensity);
        wet = softLimit(wet, 1.1);

    case 'female'
        semitones = getStylePitch(voiceConfig, 3.0 + 2.0 * intensity);
        wet = tryPitchShift(dry, semitones);
        [wet, state] = toneShape(wet, fs, state, -0.20 - 0.25 * intensity, 0.18 + 0.22 * intensity);
        wet = softLimit(wet, 1.05);

    case 'child'
        semitones = getStylePitch(voiceConfig, 5.0 + 3.0 * intensity);
        wet = tryPitchShift(dry, semitones);
        [wet, state] = toneShape(wet, fs, state, -0.35 - 0.20 * intensity, 0.24 + 0.18 * intensity);
        wet = softLimit(wet, 1.0);

    case 'elder'
        semitones = getStylePitch(voiceConfig, -1.5 - 1.5 * intensity);
        wet = tryPitchShift(dry, semitones);
        [wet, state] = toneShape(wet, fs, state, 0.12, -0.35 - 0.25 * intensity);
        wet = addRoughness(wet, fs, voiceConfig, state, 0.15 + 0.35 * intensity);
        wet = softLimit(wet, 1.0);

    case 'anonymous'
        semitones = getStylePitch(voiceConfig, -6.0 - 3.0 * intensity);
        wet = tryPitchShift(dry, semitones);
        [wet, state] = bandLimit(wet, fs, state, 300, 3400);
        wet = tanh((1.4 + intensity) * wet) / tanh(1.4 + intensity);

    case 'robot_voice'
        wet = robotVoice(dry, fs, voiceConfig, state);
        [wet, state] = toneShape(wet, fs, state, -0.05, 0.10 + 0.20 * intensity);

    otherwise
        wet = dry;
end

yFrame = (1 - mix) * dry + mix * wet;
yFrame = cleanColumn(yFrame);
yFrame = min(max(yFrame, -1), 1);
state.voice.sampleIndex = state.voice.sampleIndex + numel(yFrame);
state.voice.lastMode = voiceType;
state.voice.lastFs = fs;
end

function config = fillVoiceDefaults(config)
defaults = makeDefaultConfig();
defaultConfig = defaults.voice;
fields = fieldnames(defaultConfig);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name)
        config.(name) = defaultConfig.(name);
    end
end
end

function voiceType = getVoiceType(config)
if isfield(config, 'type') && ~isempty(config.type)
    voiceType = char(config.type);
elseif isfield(config, 'mode') && ~isempty(config.mode)
    voiceType = char(config.mode);
else
    voiceType = 'none';
end
end

function semitones = getStylePitch(config, defaultValue)
value = getFieldOrDefault(config, 'pitchShift', []);
if isempty(value) || ~isfinite(double(value)) || double(value) == 0
    semitones = defaultValue;
else
    semitones = double(value);
end
semitones = min(max(semitones, -12), 12);
end

function y = tryPitchShift(x, semitones)
y = x;
if exist('shiftPitch', 'file') == 2 && numel(x) >= 256 && abs(semitones) > 0.01
    try
        y = shiftPitch(x, semitones);
        y = cleanColumn(y);
        y = fitLength(y, numel(x));
        return;
    catch
        y = pitchFallback(x, semitones);
    end
elseif abs(semitones) > 0.01
    y = pitchFallback(x, semitones);
end
end

function y = pitchFallback(x, semitones)
% Resampling-style approximation; keeps length but is not natural pitch shifting.
n = numel(x);
if n <= 1
    y = x;
    return;
end
factor = 2 ^ (semitones / 12);
sourceIndex = 1 + mod((0:n-1).' * factor, n - 1);
y = interp1((1:n).', x, sourceIndex, 'linear', 'extrap');
y = cleanColumn(y);
end

function [y, state] = toneShape(x, fs, state, lowGain, highGain)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
[low, state.voice.eqLowPrev] = onePoleLowpass(x, fs, 350, state.voice.eqLowPrev);
[presenceLow, state.voice.eqPresencePrev] = onePoleLowpass(x, fs, 2200, state.voice.eqPresencePrev);
high = x - presenceLow;
y = x + double(lowGain) * low + double(highGain) * high;
y = normalizeIfNeeded(y);
end

function [y, state] = bandLimit(x, fs, state, lowCutoff, highCutoff)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
if ~isfield(state.voice, 'bandLowPrev')
    state.voice.bandLowPrev = 0;
end
if ~isfield(state.voice, 'bandHighPrev')
    state.voice.bandHighPrev = 0;
end
[lowPassed, state.voice.bandHighPrev] = onePoleLowpass(x, fs, highCutoff, state.voice.bandHighPrev);
[lowRumble, state.voice.bandLowPrev] = onePoleLowpass(lowPassed, fs, lowCutoff, state.voice.bandLowPrev);
y = lowPassed - lowRumble;
y = normalizeIfNeeded(y);
end

function y = addRoughness(x, fs, config, state, amount)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
roughness = clamp01(getFieldOrDefault(config, 'roughness', amount));
modFreq = abs(double(getFieldOrDefault(config, 'modFreq', 7)));
if isempty(modFreq) || ~isfinite(modFreq) || modFreq <= 0
    modFreq = 7;
end
n = (0:numel(x)-1).' + state.voice.sampleIndex;
tremolo = 1 - roughness * 0.30 + roughness * 0.30 * sin(2 * pi * modFreq * n / fs);
y = x .* tremolo;
end

function y = robotVoice(x, fs, config, state)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
intensity = clamp01(getFieldOrDefault(config, 'intensity', 0.6));
modFreq = abs(double(getFieldOrDefault(config, 'modFreq', 45)));
if isempty(modFreq) || ~isfinite(modFreq) || modFreq <= 0
    modFreq = 45;
end
modFreq = min(modFreq, fs * 0.25);
n = (0:numel(x)-1).' + state.voice.sampleIndex;
carrier = cos(2 * pi * modFreq * n / fs);
y = x .* ((1 - 0.35 * intensity) + intensity * carrier);
y = softLimit(y, 1.1 + 0.4 * intensity);
end

function [y, prev] = onePoleLowpass(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2 * pi * cutoff / fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1 - alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end

function y = softLimit(x, drive)
drive = max(0.1, double(drive));
y = tanh(drive * x) / tanh(drive);
end

function y = normalizeIfNeeded(x)
y = cleanColumn(x);
peak = max(abs(y));
if peak > 1
    y = y / peak;
end
end

function y = fitLength(y, targetLength)
y = cleanColumn(y);
if numel(y) < targetLength
    y(end + 1:targetLength, 1) = 0;
elseif numel(y) > targetLength
    y = y(1:targetLength);
end
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
