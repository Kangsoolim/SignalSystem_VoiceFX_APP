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
for k = 1:numel(noiseTypes)
    noiseConfig = config.noise;
    noiseConfig.enabled = true;
    noiseConfig.type = noiseTypes{k};
    noiseConfig.mode = 'legacy_value_should_not_override_type';
    noiseConfig.seed = 123;
    noiseConfig.snrDb = 20;
    noiseConfig.noiseLevel = 0.02;
    noiseConfig.impulseProbability = 0.01;
    noiseConfig.humAmplitude = 0.02;

    [y, state] = addNoise(x, fs, noiseConfig, state);
    y = safeLimiter(y, config);

    assert(numel(y) == numel(x), 'Noise output length must match input.');
    assert(isa(y, 'double'), 'Noise output must be double.');
    assert(iscolumn(y), 'Noise output must be a column vector.');
    assert(all(isfinite(y)), 'Noise output must not contain NaN or Inf.');
    assert(max(abs(y)) <= 1.000001, 'Noise output should stay within limiter range.');
end

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
