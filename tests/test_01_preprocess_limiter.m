%TEST_01_PREPROCESS_LIMITER Validate preprocessing and safe limiter basics.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

defaultConfig = makeDefaultConfig();
assert(defaultConfig.audio.removeDC == false, 'Default preprocessing must not force removeDC.');
assert(defaultConfig.audio.normalizeInput == false, 'Default preprocessing must not normalize per frame/input.');
assert(strcmp(defaultConfig.output.limiterMode, 'hard'), 'Default limiter mode must remain hard.');

config = makeDefaultConfig();
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.8;

fs = 16000;
t = (0:1/fs:1-1/fs).';

xMono = 0.2 * sin(2 * pi * 440 * t) + 0.1;
yDefault = preprocessAudio(xMono, fs, defaultConfig);
assertSignalContract(yDefault, numel(xMono), 1, 'Default preprocess output');
assert(abs(mean(yDefault) - mean(xMono)) < 1e-12, 'Default preprocess should not remove DC.');
assert(abs(max(abs(yDefault)) - max(abs(xMono))) < 1e-12, 'Default preprocess should not normalize input.');

yMono = preprocessAudio(xMono, fs, config);
assert(isa(yMono, 'double'), 'Mono output must be double.');
assert(iscolumn(yMono), 'Mono output must be a column vector.');
assert(numel(yMono) == numel(xMono), 'Mono output length must match input.');
assert(all(isfinite(yMono)), 'Mono output must not contain NaN or Inf.');
assert(abs(mean(yMono)) < 1e-10, 'DC component should be removed.');
assert(max(abs(yMono)) <= 0.800001, 'Normalized mono peak should be bounded.');

xStereo = [xMono, -xMono];
yStereo = preprocessAudio(xStereo, fs, config);
assert(iscolumn(yStereo), 'Stereo output must be a column vector.');
assert(numel(yStereo) == size(xStereo, 1), 'Stereo output length must match rows.');
assert(all(isfinite(yStereo)), 'Stereo output must not contain NaN or Inf.');

xMulti = [xMono, 0.5 * xMono, -0.25 * xMono];
yMulti = preprocessAudio(xMulti, fs, config);
assert(iscolumn(yMulti), 'Multi-channel output must be a column vector.');
assert(numel(yMulti) == size(xMulti, 1), 'Multi-channel output length must match rows.');
assert(all(isfinite(yMulti)), 'Multi-channel output must not contain NaN or Inf.');

xBad = [0; NaN; Inf; -Inf; 0.5];
yBad = preprocessAudio(xBad, fs, config);
assert(all(isfinite(yBad)), 'NaN and Inf values should be replaced.');
assertSignalContract(yBad, numel(xBad), 1, 'NaN/Inf preprocess output');

for fsCase = [8000, 16000, 44100, 48000]
    tCase = (0:1/fsCase:0.05).';
    xCase = [0.3 * sin(2 * pi * 220 * tCase), 0.1 * cos(2 * pi * 330 * tCase)];
    yCase = preprocessAudio(xCase, fsCase, defaultConfig);
    assertSignalContract(yCase, size(xCase, 1), 1, ['Preprocess output at fs=', num2str(fsCase)]);
end

partialConfig = struct();
partialConfig.audio = struct('normalizeInput', true, 'normalizeTargetPeak', 0.5);
yPartial = preprocessAudio(xMono, fs, partialConfig);
assert(iscolumn(yPartial), 'Partial config output must be a column vector.');
assert(max(abs(yPartial)) <= 0.500001, 'Partial config should be filled from defaults.');

[yFile, fileState] = processAudioFile(xMono, fs, config);
assert(isstruct(fileState), 'File processing must return a state struct.');
assert(numel(yFile) == numel(xMono), 'File output length must match input.');
assert(all(isfinite(yFile)), 'File output must not contain NaN or Inf.');
assert(max(abs(yFile)) <= 0.800001, 'File preprocessing should respect normalizeTargetPeak.');

yEmpty = preprocessAudio([], fs, config);
assert(isa(yEmpty, 'double'), 'Empty output must be double.');
assert(iscolumn(yEmpty), 'Empty output must be a column vector.');
assert(isempty(yEmpty), 'Empty input should remain empty.');

extremeConfig = makeDefaultConfig();
xExtreme = 1e6 * sin(2 * pi * 440 * t);
[yExtreme, extremeState] = processAudioFile(xExtreme, fs, extremeConfig);
assert(isstruct(extremeState), 'Extreme amplitude processing must return state.');
assertSignalContract(yExtreme, numel(xExtreme), 1, 'Extreme amplitude file output');
assert(max(abs(yExtreme)) <= 1.000001, 'Final file output peak must not exceed 1.');

limitConfig = makeDefaultConfig();
limitConfig.output.limitRange = [-0.5, 0.5];
xLoud = [-2; -0.25; NaN; Inf; 0.25; 2];
yLimited = safeLimiter(xLoud, limitConfig);
assert(isa(yLimited, 'double'), 'Limiter output must be double.');
assert(iscolumn(yLimited), 'Limiter output must be a column vector.');
assert(all(isfinite(yLimited)), 'Limiter output must not contain NaN or Inf.');
assert(all(yLimited >= -0.5 & yLimited <= 0.5), 'Limiter must respect limitRange.');

softConfig = limitConfig;
softConfig.output.limiterMode = 'soft';
ySoft = safeLimiter(xLoud, softConfig);
assertSignalContract(ySoft, numel(xLoud), 0.5, 'Soft limiter output');
assert(all(ySoft >= -0.5 & ySoft <= 0.5), 'Soft limiter must respect limitRange.');
assert(abs(ySoft(2)) < abs(yLimited(2)), 'Soft limiter should bend in-range samples smoothly.');

disp('test_01_preprocess_limiter passed: preprocessing and limiter basics work.');

function assertSignalContract(x, expectedLength, expectedPeak, label)
assert(isa(x, 'double'), [label, ' must be double.']);
assert(iscolumn(x), [label, ' must be a column vector.']);
assert(numel(x) == expectedLength, [label, ' length is unexpected.']);
assert(all(isfinite(x)), [label, ' must not contain NaN or Inf.']);
if ~isempty(x)
    assert(max(abs(x)) <= expectedPeak + 1e-6, [label, ' peak exceeded the expected bound.']);
end
end
