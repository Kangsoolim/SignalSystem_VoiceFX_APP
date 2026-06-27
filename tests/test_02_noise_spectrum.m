%TEST_02_NOISE_SPECTRUM Validate simple noise modes and spectrum analysis.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1-1/fs).';
x = 0.2 * sin(2 * pi * 440 * t);

config = makeDefaultConfig();
state = initProcessState(config);

noiseTypes = {'none', 'white', 'hum50', 'impulse'};
noiseOutputs = struct();
for k = 1:numel(noiseTypes)
    noiseConfig = config.noise;
    noiseConfig.enabled = true;
    noiseConfig.type = noiseTypes{k};
    noiseConfig.mode = 'legacy_value_should_not_override_type';
    noiseConfig.whiteMode = 'fixed';
    noiseConfig.seed = 123;
    noiseConfig.snrDb = 20;
    noiseConfig.noiseLevel = 0.022;
    noiseConfig.whiteFloorLevel = 0.012;
    noiseConfig.impulseProbability = 0.01;
    noiseConfig.humAmplitude = 0.03;
    if strcmp(noiseTypes{k}, 'impulse')
        noiseConfig.noiseLevel = 0.16;
    end

    [y, state] = addNoise(x, fs, noiseConfig, state);
    y = safeLimiter(y, config);

    assert(numel(y) == numel(x), 'Noise output length must match input.');
    assert(isa(y, 'double'), 'Noise output must be double.');
    assert(iscolumn(y), 'Noise output must be a column vector.');
    assert(all(isfinite(y)), 'Noise output must not contain NaN or Inf.');
    assert(max(abs(y)) <= 1.000001, 'Noise output should stay within limiter range.');
    noiseOutputs.(noiseTypes{k}) = y;
end

whiteNoise = noiseOutputs.white - x;
humNoise = noiseOutputs.hum50 - x;
impulseNoise = noiseOutputs.impulse - x;

assert(rmsValue(whiteNoise) > 0.012, 'White noise should be clearly audible above a tiny floor.');
assert(rmsValue(whiteNoise(1:round(0.1 * fs))) > 0.006, ...
    'White noise should keep a continuous low floor instead of gating to silence.');
assert(bandEnergyFraction(whiteNoise, fs, 1000, 6000) > 0.20, ...
    'White noise should keep obvious broadband high-frequency energy.');

humPeak50 = magnitudeAt(humNoise, fs, 50);
humPeak440 = magnitudeAt(humNoise, fs, 440);
assert(humPeak50 > 8 * max(humPeak440, eps), 'hum50 should be dominated by the 50 Hz component.');

impulseMask = abs(impulseNoise) > 0.05;
assert(nnz(impulseMask) > 3, 'Impulse noise should create visible clicks.');
assert(nnz(impulseMask) < 0.05 * numel(impulseNoise), 'Impulse noise should stay sparse, not become continuous clipping.');
assert(max(abs(impulseNoise)) <= 0.25, 'Impulse noise default/test level should not create explosive peaks.');

frameConfig = makeDefaultConfig();
frameConfig.audio.frameLength = 2048;
frameConfig.noise.enabled = true;
frameConfig.noise.type = 'white';
frameConfig.noise.whiteMode = 'fixed';
frameConfig.noise.noiseLevel = 0.022;
frameConfig.noise.seed = 789;
steppedInput = [zeros(fs / 4, 1); x(1:fs / 2); zeros(fs / 4, 1)];
[steppedWhite, ~] = processAudioFile(steppedInput, fs, frameConfig);
steppedNoise = steppedWhite - steppedInput;
assert(maxAdjacentFrameJumpDb(steppedNoise, frameConfig.audio.frameLength) < 4, ...
    'Fixed white noise should not pump or gate between file-processing frames.');

legacyConfig = struct();
legacyConfig.enabled = true;
legacyConfig.mode = 'white';
legacyConfig.seed = 456;
legacyConfig.snrDb = 20;
legacyConfig.noiseLevel = 0.02;
[legacyY, state] = addNoise(x, fs, legacyConfig, state);
assert(numel(legacyY) == numel(x), 'Legacy mode output length must match input.');
assert(all(isfinite(legacyY)), 'Legacy mode output must not contain NaN or Inf.');

frameConfig = makeDefaultConfig();
frameConfig.modDemod.enabled = true;
[yFrame, frameState] = processAudioFrame(x(1:257), fs, frameConfig);
assert(isstruct(frameState), 'Frame processing must return a state struct.');
assert(numel(yFrame) == 257, 'Frame output length must match input when modDemod is enabled.');
assert(all(isfinite(yFrame)), 'Frame output with modDemod placeholder must be finite.');

info = analyzeSpectrum(x, fs, config.display);
assert(isstruct(info), 'analyzeSpectrum must return a struct.');
assert(isfield(info, 'f'), 'Spectrum info must include f.');
assert(isfield(info, 'mag'), 'Spectrum info must include mag.');
assert(isfield(info, 'magDb'), 'Spectrum info must include magDb.');
assert(isfield(info, 'fs'), 'Spectrum info must include fs.');
assert(isfield(info, 'numSamples'), 'Spectrum info must include numSamples.');
assert(isfield(info, 'durationSeconds'), 'Spectrum info must include durationSeconds.');
assert(numel(info.f) == numel(info.mag), 'f and mag lengths must match.');
assert(numel(info.mag) == numel(info.magDb), 'mag and magDb lengths must match.');
assert(iscolumn(info.f), 'Frequency vector must be a column vector.');
assert(iscolumn(info.mag), 'Magnitude vector must be a column vector.');
assert(info.f(1) == 0, 'Frequency vector should start at 0 Hz.');
assert(info.f(end) <= fs / 2 + fs / numel(x), 'Frequency vector should not exceed Nyquist.');
assert(all(isfinite(info.mag)), 'Magnitude spectrum must be finite.');
assert(all(isfinite(info.magDb)), 'Magnitude dB spectrum must be finite.');

emptyInfo = analyzeSpectrum([], fs, config.display);
assert(isempty(emptyInfo.f), 'Empty spectrum should have empty f.');
assert(isempty(emptyInfo.mag), 'Empty spectrum should have empty mag.');
assert(isempty(emptyInfo.magDb), 'Empty spectrum should have empty magDb.');

disp('test_02_noise_spectrum passed: noise modes and spectrum analysis work.');

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end

function value = bandEnergyFraction(x, fs, fLow, fHigh)
x = double(x(:));
n = numel(x);
spec = abs(fft(x));
freq = (0:n-1).' * fs / n;
mask = freq >= fLow & freq <= fHigh;
totalEnergy = sum(spec .^ 2);
value = sum(spec(mask) .^ 2) / max(totalEnergy, eps);
end

function value = magnitudeAt(x, fs, frequency)
x = double(x(:));
n = numel(x);
spec = abs(fft(x));
bin = round(frequency / fs * n) + 1;
bin = min(max(bin, 1), n);
value = spec(bin) / max(n, 1);
end

function value = maxAdjacentFrameJumpDb(x, frameLength)
x = double(x(:));
numFrames = floor(numel(x) / frameLength);
frameRms = zeros(numFrames, 1);
for k = 1:numFrames
    idx = (k - 1) * frameLength + (1:frameLength);
    frameRms(k) = rmsValue(x(idx));
end
if numel(frameRms) < 2
    value = 0;
else
    jumps = abs(20 * log10(max(frameRms(2:end), eps) ./ max(frameRms(1:end-1), eps)));
    value = max(jumps);
end
end
