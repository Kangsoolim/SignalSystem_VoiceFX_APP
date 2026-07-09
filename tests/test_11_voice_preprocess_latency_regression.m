%TEST_11_VOICE_PREPROCESS_LATENCY_REGRESSION Guard voice/preprocess regressions.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.4-1/fs).';
femaleLike = 0.24 * sin(2 * pi * 260 * t) + ...
    0.16 * sin(2 * pi * 520 * t) + ...
    0.10 * sin(2 * pi * 1180 * t) + ...
    0.08 * sin(2 * pi * 2500 * t);
femaleLike = femaleLike .* (0.85 + 0.15 * sin(2 * pi * 3.5 * t));
femaleLike = femaleLike(:);

config = makeDefaultConfig();
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.22;

tFrame = (0:511).' / fs;
frame = 0.61 * sin(2 * pi * 220 * tFrame);
[frameOut, ~] = processAudioFrame(frame, fs, config, initProcessState(config));
assert(max(abs(frameOut)) > 0.40, ...
    'processAudioFrame must not apply per-frame normalizeInput.');
assert(max(abs(frameOut - frame)) < 1e-12, ...
    'Disabled frame pipeline should only clean shape/type.');

baseConfig = makeDefaultConfig();
baseConfig.audio.removeDC = true;
baseConfig.audio.normalizeInput = true;
baseConfig.audio.normalizeTargetPeak = 0.82;
baseConfig.audio.frameLength = 512;

[base, ~] = processAudioFile(femaleLike, fs, baseConfig);

voiceModes = {'male', 'female', 'child', 'elder', 'anonymous', 'robot_voice'};
earlyThresholds = struct('male', 0.010, 'female', 0.008, ...
    'child', 0.012, 'elder', 0.009, 'anonymous', 0.014, ...
    'robot_voice', 0.010);

earlyCount = round(0.20 * fs);
voiceOutputs = struct();
for k = 1:numel(voiceModes)
    modeName = voiceModes{k};
    voiceConfig = baseConfig;
    voiceConfig.voice.enabled = true;
    voiceConfig.voice.type = modeName;
    voiceConfig.voice.mode = modeName;
    voiceConfig.voice.intensity = 0.82;
    voiceConfig.voice.mix = 1.0;
    voiceConfig.voice.roughness = 0.35;

    [y, styleState] = processAudioFile(femaleLike, fs, voiceConfig);
    assert(isfield(styleState.voice, 'lastMode'), ...
        [modeName, ' voice state should keep processing history.']);
    if ~strcmp(modeName, 'robot_voice')
        assert(isfield(styleState.voice, 'adaptiveConfig'), ...
            [modeName, ' should store adaptive or fallback voice config.']);
    end
    assert(numel(y) == numel(femaleLike), ...
        [modeName, ' output length must match input.']);
    assert(all(isfinite(y)), [modeName, ' output must be finite.']);
    assert(max(abs(y)) <= 1.000001, ...
        [modeName, ' output must stay in [-1, 1].']);

    earlyDelta = rmsValue(y(1:earlyCount) - base(1:earlyCount));
    totalDelta = rmsValue(y - base);
    assert(earlyDelta > earlyThresholds.(modeName), ...
        [modeName, ' style must be audible from the first 0.2 seconds.']);
    assert(totalDelta > earlyThresholds.(modeName) * 1.6, ...
        [modeName, ' style should not be near pass-through.']);
    assert(frameBoundaryJumpRatio(y, baseConfig.audio.frameLength) < 8.0, ...
        [modeName, ' output has suspicious frame-boundary jumps.']);

    voiceOutputs.(modeName) = y;
end

baseCentroid = spectralCentroid(base, fs);
maleCentroid = spectralCentroid(voiceOutputs.male, fs);
elderCentroid = spectralCentroid(voiceOutputs.elder, fs);
assert(maleCentroid < baseCentroid * 0.97, ...
    'Male style should darken/lower a bright source.');
assert(elderCentroid < baseCentroid * 0.99, ...
    'Elder style should darken a bright source.');

disp('test_11_voice_preprocess_latency_regression passed: frame preprocessing and voice styles start immediately.');

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end

function value = spectralCentroid(x, fs)
x = double(x(:));
x(~isfinite(x)) = 0;
n = numel(x);
if n == 0
    value = 0;
    return;
end
idx = (0:n-1).';
w = 0.5 - 0.5 * cos(2 * pi * idx / max(n - 1, 1));
mag = abs(fft(x .* w));
count = floor(n / 2) + 1;
mag = mag(1:count);
powerMag = mag .^ 2;
freq = (0:count-1).' * fs / n;
value = sum(freq .* powerMag) / (sum(powerMag) + eps);
end

function ratio = frameBoundaryJumpRatio(x, frameLength)
x = double(x(:));
if numel(x) <= frameLength + 2
    ratio = 0;
    return;
end
diffAbs = abs(diff(x));
typicalJump = median(diffAbs) + eps;
boundaryIdx = frameLength:frameLength:numel(x)-1;
boundaryJump = max(abs(x(boundaryIdx + 1) - x(boundaryIdx)));
ratio = boundaryJump / typicalJump;
end