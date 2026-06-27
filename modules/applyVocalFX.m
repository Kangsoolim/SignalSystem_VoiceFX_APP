function [yFrame, state] = applyVocalFX(xFrame, fs, fxConfig, state)
%APPLYVOCALFX Apply lightweight vocal/device/digital effects.
%   Supported modes are none, telephone, walkie_talkie, radio, lofi,
%   bitcrusher, and robot. The implementation stays causal and frame-safe.

if nargin < 3 || isempty(fxConfig)
    fxConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
inputFxConfig = fxConfig;
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

requestedFxType = getFxType(fxConfig);
fxType = canonicalFxType(requestedFxType);
if strcmpi(fxType, 'none') || isempty(yFrame)
    return;
end

dry = yFrame;
presetParams = getPresetParams(fxConfig, requestedFxType);
if ~hasStructFields(presetParams) && ~strcmpi(requestedFxType, fxType)
    presetParams = getPresetParams(fxConfig, fxType);
end
defaultConfig = makeDefaultConfig();
defaultFxConfig = defaultConfig.fx;
mix = clamp01(getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'mix', 1.0));
intensity = clamp01(getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'intensity', 0.6));

if ~isfield(state.fx, 'sampleIndex')
    state.fx.sampleIndex = 0;
end

switch lower(fxType)
    case 'telephone'
        lowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'lowCutoff', 300);
        highCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'highCutoff', 3400);
        order = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'filterOrder', 4);
        drive = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'drive', 1.18);
        [wet, state] = filterTone(dry, fs, lowCutoff, highCutoff, 'bandpass', order, fxType, state);
        wet = softDrive(wet, drive + 0.20 * intensity);

    case 'walkie_talkie'
        lowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'lowCutoff', 380);
        highCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'highCutoff', 3000);
        order = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'filterOrder', 4);
        drive = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'drive', 1.45);
        [wet, state] = filterTone(dry, fs, lowCutoff, highCutoff, 'bandpass', order, fxType, state);
        wet = softDrive(wet, drive + 0.25 * intensity);
        if ~isempty(fs) && isfinite(fs) && fs > 0
            n = (0:numel(wet)-1).' + state.fx.sampleIndex;
            toneLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'toneLevel', 0.004);
            toneFreq = min(getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'toneFreq', 2100), 0.42 * fs);
            noiseLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'noiseLevel', 0.006);
            wet = wet + toneLevel * intensity * sin(2 * pi * toneFreq * n / fs);
            wet = wet + noiseLevel * intensity * deterministicNoise(n);
        end

    case 'radio'
        lowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'lowCutoff', 170);
        highCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'highCutoff', 4700);
        order = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'filterOrder', 3);
        drive = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'drive', 1.10);
        [wet, state] = filterTone(dry, fs, lowCutoff, highCutoff, 'bandpass', order, fxType, state);
        wet = softDrive(wet, drive + 0.12 * intensity);
        if ~isempty(fs) && isfinite(fs) && fs > 0
            n = (0:numel(wet)-1).' + state.fx.sampleIndex;
            noiseLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'noiseLevel', 0.003);
            wet = wet + noiseLevel * intensity * deterministicNoise(n + 1709);
        end
        targetRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'targetSampleRate', []);
        if ~isempty(targetRate)
            [wet, state] = sampleHold(wet, fs, inputFxConfig, fxConfig, defaultFxConfig, presetParams, state);
        end
        bitDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'bitDepth', []);
        if ~isempty(bitDepth)
            wet = quantizeSignal(wet, max(7, round(double(bitDepth) - intensity)));
        end
        postLowpass = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'postLowpassCutoff', []);
        if ~isempty(postLowpass)
            [wet, state] = filterTone(wet, fs, [], postLowpass, 'lowpass', 2, [fxType, '_post'], state);
        end

    case 'lofi'
        highCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'lowpassCutoff', 3600);
        order = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'filterOrder', 3);
        bitDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'bitDepth', 8);
        [wet, state] = filterTone(dry, fs, [], highCutoff, 'lowpass', order, fxType, state);
        [wet, state] = sampleHold(wet, fs, inputFxConfig, fxConfig, defaultFxConfig, presetParams, state);
        wet = quantizeSignal(wet, max(6, round(bitDepth - 1.5 * intensity)));
        postLowpass = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'postLowpassCutoff', []);
        if ~isempty(postLowpass)
            [wet, state] = filterTone(wet, fs, [], postLowpass, 'lowpass', 2, [fxType, '_post'], state);
        end

    case 'bitcrusher'
        bitDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'bitDepth', 8);
        bitDepth = round(max(4, min(16, double(bitDepth) - round(2 * intensity))));
        preGain = max(1.0, double(getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'preGain', 1.0)));
        makeupGain = max(0.1, double(getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'makeupGain', 1.0)));
        wet = quantizeSignal(limitInternal(dry * preGain), bitDepth) / preGain;
        wet = wet * makeupGain;
        targetRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'targetSampleRate', []);
        if ~isempty(targetRate)
            [wet, state] = sampleHold(wet, fs, inputFxConfig, fxConfig, defaultFxConfig, presetParams, state);
        end
        postLowpass = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'postLowpassCutoff', []);
        if ~isempty(postLowpass)
            [wet, state] = filterTone(wet, fs, [], postLowpass, 'lowpass', 2, [fxType, '_post'], state);
        end

    case 'gramophone'
        lowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'lowCutoff', 180);
        highCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'highCutoff', 4300);
        order = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'filterOrder', 3);
        drive = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'drive', 1.65);
        [wet, state] = filterTone(dry, fs, lowCutoff, highCutoff, 'bandpass', order, fxType, state);
        hornLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'hornLowCutoff', []);
        hornHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'hornHighCutoff', []);
        hornGain = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'hornGain', 0);
        if ~isempty(hornLowCutoff) && ~isempty(hornHighCutoff) && hornGain > 0
            [hornBand, state] = filterTone(wet, fs, hornLowCutoff, hornHighCutoff, 'bandpass', 3, [fxType, '_horn'], state);
            wet = wet + hornGain * intensity * hornBand;
        end
        nasalLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'nasalLowCutoff', []);
        nasalHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'nasalHighCutoff', []);
        nasalGain = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'nasalGain', 0);
        if ~isempty(nasalLowCutoff) && ~isempty(nasalHighCutoff) && nasalGain > 0
            [nasalBand, state] = filterTone(wet, fs, nasalLowCutoff, nasalHighCutoff, 'bandpass', 3, [fxType, '_nasal'], state);
            wet = wet + nasalGain * intensity * nasalBand;
        end
        mudLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'mudLowCutoff', []);
        mudHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'mudHighCutoff', []);
        mudCut = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'mudCut', 0);
        if ~isempty(mudLowCutoff) && ~isempty(mudHighCutoff) && mudCut > 0
            [mudBand, state] = filterTone(wet, fs, mudLowCutoff, mudHighCutoff, 'bandpass', 2, [fxType, '_mud'], state);
            wet = wet - mudCut * intensity * mudBand;
        end
        hornDelayMs = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'hornDelayMs', []);
        if ~isempty(hornDelayMs)
            hornDelayFeedback = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'hornDelayFeedback', 0.25);
            [wet, state] = gramophoneHornDelay(wet, fs, hornDelayMs, hornDelayFeedback, [fxType, '_horn_delay'], state);
        end
        wowDelayDepthMs = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wowDelayDepthMs', []);
        flutterDelayDepthMs = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'flutterDelayDepthMs', []);
        if ~isempty(wowDelayDepthMs) || ~isempty(flutterDelayDepthMs)
            wowRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wowRate', 0.75);
            flutterRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'flutterRate', 6.0);
            [wet, state] = gramophoneWarble(wet, fs, wowDelayDepthMs, wowRate, ...
                flutterDelayDepthMs, flutterRate, [fxType, '_warble'], state);
        end
        targetRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'targetSampleRate', []);
        if ~isempty(targetRate)
            [wet, state] = sampleHold(wet, fs, inputFxConfig, fxConfig, defaultFxConfig, presetParams, state);
        end
        bitDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'bitDepth', []);
        if ~isempty(bitDepth)
            wet = quantizeSignal(wet, max(7, round(double(bitDepth) - 0.5 * intensity)));
        end
        wet = softDrive(wet, drive + 0.20 * intensity);
        if ~isempty(fs) && isfinite(fs) && fs > 0
            n = (0:numel(wet)-1).' + state.fx.sampleIndex;
            wowDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wowDepth', 0.035);
            wowRate = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wowRate', 0.75);
            surfaceNoiseLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'surfaceNoiseLevel', 0.0055);
            crackleLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'crackleLevel', 0.030);
            crackleDensity = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'crackleDensity', 0.018);
            crackleSmoothSamples = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'crackleSmoothSamples', 7);
            wow = 1 + wowDepth * intensity * sin(2 * pi * wowRate * n / fs);
            wet = wet .* wow;
            surfaceNoise = deterministicNoise(n + 3029);
            surfaceNoiseLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'surfaceNoiseLowCutoff', []);
            surfaceNoiseHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'surfaceNoiseHighCutoff', []);
            if ~isempty(surfaceNoiseLowCutoff) && ~isempty(surfaceNoiseHighCutoff)
                [surfaceNoise, state] = filterTone(surfaceNoise, fs, surfaceNoiseLowCutoff, ...
                    surfaceNoiseHighCutoff, 'bandpass', 2, [fxType, '_surface_noise'], state);
            end
            wet = wet + surfaceNoiseLevel * intensity * surfaceNoise;

            crackle = crackleNoise(n, crackleDensity * intensity, crackleLevel, crackleSmoothSamples);
            crackleLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'crackleLowCutoff', []);
            crackleHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'crackleHighCutoff', []);
            if ~isempty(crackleLowCutoff) && ~isempty(crackleHighCutoff)
                [crackle, state] = filterTone(crackle, fs, crackleLowCutoff, ...
                    crackleHighCutoff, 'bandpass', 2, [fxType, '_crackle'], state);
            end
            wet = wet + crackle;

            clickPopDensity = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'clickPopDensity', 0);
            clickPopLevel = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'clickPopLevel', 0);
            clickPopWidthMs = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'clickPopWidthMs', 1.4);
            if clickPopDensity > 0 && clickPopLevel > 0
                clicks = clickPopNoise(n, fs, clickPopDensity * intensity, clickPopLevel, clickPopWidthMs);
                clickLowCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'clickLowCutoff', []);
                clickHighCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'clickHighCutoff', []);
                if ~isempty(clickLowCutoff) && ~isempty(clickHighCutoff)
                    [clicks, state] = filterTone(clicks, fs, clickLowCutoff, ...
                        clickHighCutoff, 'bandpass', 2, [fxType, '_clicks'], state);
                end
                wet = wet + clicks;
            end

            wearDropDensity = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wearDropDensity', 0);
            wearDropDepth = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wearDropDepth', 0);
            wearDropDurationMs = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'wearDropDurationMs', 35);
            if wearDropDensity > 0 && wearDropDepth > 0
                wet = wet .* gramophoneWearGain(n, fs, wearDropDensity * intensity, ...
                    wearDropDepth, wearDropDurationMs);
            end
        end
        postLowpass = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'postLowpassCutoff', []);
        if ~isempty(postLowpass)
            [wet, state] = filterTone(wet, fs, [], postLowpass, 'lowpass', 2, [fxType, '_post'], state);
        end
        saturationDrive = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'saturationDrive', 1.10);
        saturationCeiling = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'saturationCeiling', 0.94);
        saturationDrive = max(0.1, double(saturationDrive));
        saturationCeiling = min(max(double(saturationCeiling), 0.1), 1.0);
        wet = saturationCeiling * tanh(saturationDrive * wet) / tanh(saturationDrive);
        onsetSuppressAmount = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'onsetSuppressAmount', []);
        if ~isempty(onsetSuppressAmount)
            onsetSuppressCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'onsetSuppressCutoff', 18);
            onsetReleaseCutoff = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'onsetReleaseCutoff', 5);
            [wet, state] = suppressGramophoneOnsets(wet, dry, fs, onsetSuppressAmount, ...
                onsetSuppressCutoff, onsetReleaseCutoff, [fxType, '_onset'], state);
        end
        transientSlopeLimit = getFxParam(inputFxConfig, fxConfig, defaultFxConfig, presetParams, 'transientSlopeLimit', []);
        if ~isempty(transientSlopeLimit)
            [wet, state] = limitSlew(wet, transientSlopeLimit, [fxType, '_slew'], state);
        end

    case 'robot'
        [wet, state] = robotVocoder(dry, fs, inputFxConfig, fxConfig, defaultFxConfig, presetParams, state);

    otherwise
        wet = dry;
end

yFrame = (1 - mix) * dry + mix * wet;
yFrame = cleanColumn(yFrame);
yFrame = limitInternal(yFrame);
state.fx.sampleIndex = state.fx.sampleIndex + numel(yFrame);
state.fx.lastMode = requestedFxType;
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

function fxType = canonicalFxType(fxType)
fxType = char(fxType);
lowerType = lower(fxType);
if strncmp(lowerType, 'gramophone_', numel('gramophone_')) || ...
        strcmp(lowerType, 'phonograph') || strcmp(lowerType, 'old_record') || ...
        strcmp(lowerType, 'old-record') || strcmp(lowerType, 'vinyl')
    fxType = 'gramophone';
end
end

function presetParams = getPresetParams(config, fxType)
presetParams = struct();
if isfield(config, 'presets') && isstruct(config.presets) && isfield(config.presets, fxType)
    presetParams = config.presets.(fxType);
end
end

function tf = hasStructFields(value)
tf = isstruct(value) && ~isempty(fieldnames(value));
end

function [wet, state] = filterTone(x, fs, lowCutoff, highCutoff, filterKind, order, modeName, state)
wet = x;
if isempty(fs) || ~isfinite(fs) || fs <= 0
    return;
end

[b, a, signature] = designToneFilter(fs, lowCutoff, highCutoff, filterKind, order, modeName);
ziLength = max(numel(a), numel(b)) - 1;
if ziLength > 0
    if ~isfield(state.fx, 'filterStates') || ~isstruct(state.fx.filterStates)
        state.fx.filterStates = struct();
    end
    stateKey = makeFilterStateKey(signature);
    if ~isfield(state.fx.filterStates, stateKey) || numel(state.fx.filterStates.(stateKey)) ~= ziLength
        zi = zeros(ziLength, 1);
    else
        zi = state.fx.filterStates.(stateKey);
    end
    [wet, state.fx.filterStates.(stateKey)] = filter(b, a, x, zi);
    state.fx.filterZi = state.fx.filterStates.(stateKey);
else
    wet = filter(b, a, x);
    state.fx.filterZi = [];
end
state.fx.filterSignature = signature;
end

function stateKey = makeFilterStateKey(signature)
codes = double(char(signature));
weights = 1:numel(codes);
hashValue = mod(sum(codes .* weights), 2147483647);
stateKey = sprintf('f_%d', round(hashValue));
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

function [y, state] = sampleHold(x, fs, inputConfig, config, defaultConfig, presetParams, state)
intensity = clamp01(getFxParam(inputConfig, config, defaultConfig, presetParams, 'intensity', 0.6));
targetRate = getFxParam(inputConfig, config, defaultConfig, presetParams, 'targetSampleRate', 9000);
if isempty(fs) || ~isfinite(fs) || fs <= 0 || isempty(targetRate) || ~isfinite(double(targetRate)) || targetRate <= 0
    holdSamples = max(1, round(1 + 4 * intensity));
else
    holdSamples = max(1, round(fs / min(double(targetRate), fs)));
    holdSamples = round(1 + intensity * max(0, holdSamples - 1));
end
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

function [y, state] = robotVocoder(x, fs, inputConfig, config, defaultConfig, presetParams, state)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
carrierFreq = abs(double(getFxParam(inputConfig, config, defaultConfig, presetParams, 'carrierFreq', 92)));
if isempty(carrierFreq) || ~isfinite(carrierFreq) || carrierFreq <= 0
    carrierFreq = 92;
end
carrierFreq = min(carrierFreq, fs * 0.20);
intensity = clamp01(getFxParam(inputConfig, config, defaultConfig, presetParams, 'intensity', 0.6));
envelopeCutoff = getFxParam(inputConfig, config, defaultConfig, presetParams, 'envelopeCutoff', 32);
robotGain = max(0.1, double(getFxParam(inputConfig, config, defaultConfig, presetParams, 'robotGain', 2.35)));
noiseCarrierMix = clamp01(getFxParam(inputConfig, config, defaultConfig, presetParams, 'noiseCarrierMix', 0.16));
sibilanceMix = clamp01(getFxParam(inputConfig, config, defaultConfig, presetParams, 'sibilanceMix', 0.20));
clarityMix = clamp01(getFxParam(inputConfig, config, defaultConfig, presetParams, 'clarityMix', 0.0));
n = (0:numel(x)-1).' + state.fx.sampleIndex;
saw = makeSawCarrier(n, fs, carrierFreq);
noiseCarrier = deterministicNoise(n + 5101);
carrier = (1 - noiseCarrierMix) * saw + noiseCarrierMix * noiseCarrier;
bands = robotBands(fs);
bandWeights = [1.15, 1.05, 1.00, 0.86, 0.68, 0.46];
y = zeros(size(x));
for k = 1:size(bands, 1)
    lowCutoff = bands(k, 1);
    highCutoff = bands(k, 2);
    [speechBand, state] = filterTone(x, fs, lowCutoff, highCutoff, 'bandpass', 2, sprintf('robot_env_%d', k), state);
    [envelope, state] = filterTone(abs(speechBand), fs, [], envelopeCutoff, 'lowpass', 1, sprintf('robot_env_lp_%d', k), state);
    [carrierBand, state] = filterTone(carrier, fs, lowCutoff, highCutoff, 'bandpass', 2, sprintf('robot_car_%d', k), state);
    y = y + bandWeights(k) * envelope .* carrierBand;
end

if sibilanceMix > 0
    [sibilanceEnvSource, state] = filterTone(x, fs, min(2600, 0.20 * fs), min(5600, 0.44 * fs), ...
        'bandpass', 2, 'robot_sibilance_env', state);
    [sibilanceEnv, state] = filterTone(abs(sibilanceEnvSource), fs, [], max(30, envelopeCutoff * 1.5), ...
        'lowpass', 1, 'robot_sibilance_lp', state);
    [sibilanceCarrier, state] = filterTone(noiseCarrier, fs, min(2200, 0.20 * fs), min(5200, 0.44 * fs), ...
        'bandpass', 2, 'robot_sibilance_carrier', state);
    y = y + sibilanceMix * sibilanceEnv .* sibilanceCarrier;
end

if clarityMix > 0
    [clarityEnvSource, state] = filterTone(x, fs, 900, min(3600, 0.44 * fs), ...
        'bandpass', 2, 'robot_clarity_env', state);
    [clarityEnv, state] = filterTone(abs(clarityEnvSource), fs, [], max(45, envelopeCutoff * 1.8), ...
        'lowpass', 1, 'robot_clarity_lp', state);
    clarityCarrier = 0.72 * sin(2 * pi * 4 * carrierFreq * n / fs) + ...
        0.28 * sin(2 * pi * 7 * carrierFreq * n / fs);
    [clarityCarrier, state] = filterTone(clarityCarrier, fs, 900, min(3600, 0.44 * fs), ...
        'bandpass', 2, 'robot_clarity_carrier', state);
    y = y + clarityMix * clarityEnv .* clarityCarrier;
end

y = robotGain * y;
y = softDrive(y, 1.15 + 0.45 * intensity);
postLowpass = getFxParam(inputConfig, config, defaultConfig, presetParams, 'postLowpassCutoff', []);
if ~isempty(postLowpass)
    [y, state] = filterTone(y, fs, [], postLowpass, 'lowpass', 2, 'robot_post', state);
end
y = (1 - intensity) * lowRobotReference(x, fs, state) + intensity * y;
end

function carrier = makeSawCarrier(n, fs, freq)
phase = mod(freq * double(n(:)) / fs, 1);
carrier = 2 * phase - 1;
carrier = carrier + 0.35 * sin(2 * pi * 2 * freq * double(n(:)) / fs);
carrier = carrier / max(max(abs(carrier)), eps);
end

function bands = robotBands(fs)
nyquist = fs / 2;
bands = [
    180, 340;
    340, 620;
    620, 1050;
    1050, 1700;
    1700, 2700;
    2700, min(4200, 0.44 * fs)
];
bands(:, 1) = min(bands(:, 1), nyquist * 0.80);
bands(:, 2) = min(bands(:, 2), nyquist * 0.92);
for k = 1:size(bands, 1)
    if bands(k, 2) <= bands(k, 1)
        bands(k, 2) = min(nyquist * 0.95, bands(k, 1) + 120);
    end
end
end

function y = lowRobotReference(x, fs, state) %#ok<INUSD>
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = zeros(size(x));
else
    y = 0.05 * x;
end
end

function [y, state] = gramophoneHornDelay(x, fs, delayMs, feedback, keyName, state)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
delaySamples = max(1, round(double(delayMs) * fs / 1000));
feedback = min(max(double(feedback), 0), 0.85);
stateKey = makeFilterStateKey(keyName);
if ~isfield(state.fx, 'delayStates') || ~isstruct(state.fx.delayStates)
    state.fx.delayStates = struct();
end
if ~isfield(state.fx.delayStates, stateKey) || numel(state.fx.delayStates.(stateKey)) ~= delaySamples
    buffer = zeros(delaySamples, 1);
else
    buffer = state.fx.delayStates.(stateKey);
end
if ~isfield(state.fx, 'delayWriteIndices') || ~isstruct(state.fx.delayWriteIndices)
    state.fx.delayWriteIndices = struct();
end
if isfield(state.fx.delayWriteIndices, stateKey) && ...
        isfinite(state.fx.delayWriteIndices.(stateKey)) && ...
        state.fx.delayWriteIndices.(stateKey) >= 1 && ...
        state.fx.delayWriteIndices.(stateKey) <= delaySamples
    writeIndex = round(state.fx.delayWriteIndices.(stateKey));
else
    writeIndex = 1;
end
y = zeros(size(x));
for n = 1:numel(x)
    delayed = buffer(writeIndex);
    y(n) = x(n) + feedback * delayed;
    buffer(writeIndex) = y(n);
    writeIndex = writeIndex + 1;
    if writeIndex > delaySamples
        writeIndex = 1;
    end
end
state.fx.delayStates.(stateKey) = buffer;
state.fx.delayWriteIndices.(stateKey) = writeIndex;
y = y / max(1, 1 + 0.5 * feedback);
end

function [y, state] = gramophoneWarble(x, fs, wowDepthMs, wowRate, flutterDepthMs, flutterRate, keyName, state)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    y = x;
    return;
end
wowDepthMs = max(0, double(emptyDefault(wowDepthMs, 0)));
flutterDepthMs = max(0, double(emptyDefault(flutterDepthMs, 0)));
if wowDepthMs <= 0 && flutterDepthMs <= 0
    y = x;
    return;
end

wowRate = max(0, double(emptyDefault(wowRate, 0.75)));
flutterRate = max(0, double(emptyDefault(flutterRate, 6.0)));
wowDepthSamples = wowDepthMs * fs / 1000;
flutterDepthSamples = flutterDepthMs * fs / 1000;
baseDelaySamples = max(3, ceil(wowDepthSamples + flutterDepthSamples) + 3);
historyLength = baseDelaySamples + ceil(wowDepthSamples + flutterDepthSamples) + 4;

stateKey = makeFilterStateKey(keyName);
if ~isfield(state.fx, 'warbleStates') || ~isstruct(state.fx.warbleStates)
    state.fx.warbleStates = struct();
end
if isfield(state.fx.warbleStates, stateKey) && numel(state.fx.warbleStates.(stateKey)) == historyLength
    history = state.fx.warbleStates.(stateKey);
else
    history = repmat(x(1), historyLength, 1);
end

extended = [history(:); x(:)];
currentOffset = numel(history);
y = zeros(size(x));
for k = 1:numel(x)
    sampleNumber = double(state.fx.sampleIndex + k - 1);
    variableDelay = 0;
    if wowDepthSamples > 0 && wowRate > 0
        variableDelay = variableDelay + wowDepthSamples * sin(2 * pi * wowRate * sampleNumber / fs);
    end
    if flutterDepthSamples > 0 && flutterRate > 0
        variableDelay = variableDelay + flutterDepthSamples * sin(2 * pi * flutterRate * sampleNumber / fs + 0.7);
    end
    readPos = currentOffset + k - baseDelaySamples - variableDelay;
    readPos = min(max(readPos, 1), numel(extended) - 1);
    leftIndex = floor(readPos);
    frac = readPos - leftIndex;
    y(k) = (1 - frac) * extended(leftIndex) + frac * extended(leftIndex + 1);
end

state.fx.warbleStates.(stateKey) = extended(end-historyLength+1:end);
end

function [envelope, state] = smoothRobotEnvelope(x, fs, cutoff, state)
cutoff = max(1, min(double(cutoff), 0.20 * fs));
alpha = exp(-2 * pi * cutoff / fs);
if ~isfield(state.fx, 'robotEnvelope') || isempty(state.fx.robotEnvelope) || ~isfinite(state.fx.robotEnvelope)
    previous = 0;
else
    previous = state.fx.robotEnvelope;
end
envelope = zeros(size(x));
for n = 1:numel(x)
    previous = alpha * previous + (1 - alpha) * x(n);
    envelope(n) = previous;
end
state.fx.robotEnvelope = previous;
end

function value = getFxParam(inputConfig, config, defaultConfig, presetParams, fieldName, fallbackValue)
if isfield(inputConfig, 'params') && isstruct(inputConfig.params) && ...
        isfield(inputConfig.params, fieldName) && ~isempty(inputConfig.params.(fieldName))
    value = inputConfig.params.(fieldName);
    return;
end

if isfield(inputConfig, fieldName) && ~isempty(inputConfig.(fieldName)) && ...
        (~isfield(defaultConfig, fieldName) || ~isequal(inputConfig.(fieldName), defaultConfig.(fieldName)))
    value = inputConfig.(fieldName);
    return;
end

if isfield(presetParams, fieldName) && ~isempty(presetParams.(fieldName))
    value = presetParams.(fieldName);
    return;
end

if isfield(config, fieldName) && ~isempty(config.(fieldName))
    value = config.(fieldName);
else
    value = fallbackValue;
end
end

function y = deterministicNoise(n)
y = 2 * mod(sin((double(n(:)) + 1) * 12.9898) * 43758.5453, 1) - 1;
end

function y = crackleNoise(n, density, level, smoothSamples)
density = min(max(double(density), 0), 0.25);
level = max(0, double(level));
smoothSamples = max(1, round(double(smoothSamples)));
randomValues = mod(sin((double(n(:)) + 11) * 78.233) * 15731.743, 1);
mask = randomValues > (1 - density);
polarity = sign(deterministicNoise(n + 7919));
polarity(polarity == 0) = 1;
y = level * mask .* polarity .* (0.35 + 0.65 * abs(deterministicNoise(n + 2311)));
if smoothSamples > 1
    window = hannLocal(smoothSamples);
    y = conv(y, window / max(sum(window), eps), 'same');
end
end

function y = clickPopNoise(n, fs, densityPerSecond, level, widthMs)
densityPerSecond = max(0, double(densityPerSecond));
level = max(0, double(level));
if isempty(fs) || ~isfinite(fs) || fs <= 0 || densityPerSecond <= 0 || level <= 0
    y = zeros(size(n(:)));
    return;
end
probability = min(0.35, densityPerSecond / fs);
randomValues = mod(sin((double(n(:)) + 503) * 91.713) * 24137.281, 1);
events = randomValues > (1 - probability);
polarity = sign(deterministicNoise(n + 14281));
polarity(polarity == 0) = 1;
amplitude = level * events .* polarity .* (0.65 + 0.35 * abs(deterministicNoise(n + 1717)));
widthSamples = max(1, round(double(widthMs) * fs / 1000));
shapeIndex = (0:widthSamples-1).';
shape = exp(-5 * shapeIndex / max(widthSamples - 1, 1));
shape(1) = 1;
y = conv(amplitude, shape, 'same');
end

function gain = gramophoneWearGain(n, fs, densityPerSecond, depth, durationMs)
gain = ones(size(n(:)));
if isempty(fs) || ~isfinite(fs) || fs <= 0
    return;
end
densityPerSecond = max(0, double(densityPerSecond));
depth = min(max(double(depth), 0), 0.85);
if densityPerSecond <= 0 || depth <= 0
    return;
end
probability = min(0.25, densityPerSecond / fs);
randomValues = mod(sin((double(n(:)) + 211) * 43.377) * 35719.121, 1);
events = double(randomValues > (1 - probability));
widthSamples = max(2, round(double(durationMs) * fs / 1000));
window = hannLocal(widthSamples);
dips = conv(events, window / max(max(window), eps), 'same');
dips = min(dips, 1);
gain = 1 - depth * dips;
end

function w = hannLocal(n)
if n <= 1
    w = 1;
else
    idx = (0:n-1).';
    w = 0.5 - 0.5 * cos(2 * pi * idx / (n - 1));
end
end

function [y, state] = limitSlew(x, maxStep, keyName, state)
y = double(x(:));
maxStep = abs(double(maxStep));
if isempty(y) || ~isfinite(maxStep) || maxStep <= 0
    return;
end
stateKey = makeFilterStateKey(keyName);
if ~isfield(state.fx, 'slewStates') || ~isstruct(state.fx.slewStates)
    state.fx.slewStates = struct();
end
if isfield(state.fx.slewStates, stateKey) && isfinite(state.fx.slewStates.(stateKey))
    previous = state.fx.slewStates.(stateKey);
else
    previous = y(1);
end
for k = 1:numel(y)
    delta = y(k) - previous;
    if delta > maxStep
        y(k) = previous + maxStep;
    elseif delta < -maxStep
        y(k) = previous - maxStep;
    end
    previous = y(k);
end
state.fx.slewStates.(stateKey) = previous;
end

function [y, state] = suppressGramophoneOnsets(wet, dry, fs, amount, attackCutoff, releaseCutoff, keyName, state)
y = double(wet(:));
dry = double(dry(:));
if isempty(y) || isempty(fs) || ~isfinite(fs) || fs <= 0
    return;
end
amount = min(max(double(amount), 0), 0.9);
attackAlpha = exp(-2 * pi * max(1, double(attackCutoff)) / fs);
releaseAlpha = exp(-2 * pi * max(1, double(releaseCutoff)) / fs);
stateKey = makeFilterStateKey(keyName);
if ~isfield(state.fx, 'onsetStates') || ~isstruct(state.fx.onsetStates)
    state.fx.onsetStates = struct();
end
if isfield(state.fx.onsetStates, stateKey)
    s = state.fx.onsetStates.(stateKey);
else
    s = struct('fast', 0, 'slow', 0);
end
gain = ones(size(y));
for k = 1:numel(y)
    level = abs(dry(k));
    s.fast = attackAlpha * s.fast + (1 - attackAlpha) * level;
    s.slow = releaseAlpha * s.slow + (1 - releaseAlpha) * level;
    onsetRatio = max(0, (s.fast - 1.45 * s.slow) / max(s.fast, 1e-6));
    gain(k) = 1 - amount * min(onsetRatio * 2.5, 1);
end
state.fx.onsetStates.(stateKey) = s;
y = y .* gain;
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

function value = emptyDefault(value, defaultValue)
if isempty(value) || ~isfinite(double(value))
    value = defaultValue;
end
end
