%TEST_09_PREPROCESS_VALIDATION Validate preprocessing artifact generation.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

sampleFiles = dir(fullfile(projectRoot, 'samples', '*.wav'));
assert(~isempty(sampleFiles), 'samples/ must contain at least one .wav file.');

run(fullfile(projectRoot, 'scripts', 'run_preprocess_validation.m'));

outputRoot = fullfile(projectRoot, 'results', 'preprocess_validation');
assert(exist(outputRoot, 'dir') == 7, 'results/preprocess_validation/ should be generated.');

summaryCsv = fullfile(outputRoot, 'preprocess_summary.csv');
assert(exist(summaryCsv, 'file') == 2, 'preprocess_summary.csv should be generated.');

for k = 1:numel(sampleFiles)
    safeName = makeSafeName(localEraseExtension(sampleFiles(k).name));
    sampleOutputDir = fullfile(outputRoot, safeName);
    assert(exist(sampleOutputDir, 'dir') == 7, ['Missing output folder for sample: ', sampleFiles(k).name]);

    requiredFiles = {
        fullfile(sampleOutputDir, 'audio', '01_preprocess_default.wav');
        fullfile(sampleOutputDir, 'audio', '03_preprocess_normalized_peak_080.wav');
        fullfile(sampleOutputDir, 'audio', '05_safe_limiter_half_range.wav');
        fullfile(sampleOutputDir, 'figures', 'preprocess_waveform_overview.png');
        fullfile(sampleOutputDir, 'figures', 'preprocess_spectrum_overview.png');
        fullfile(sampleOutputDir, 'figures', 'preprocess_peak_dc_stats.png');
        fullfile(sampleOutputDir, 'summary.md')
    };

    for n = 1:numel(requiredFiles)
        assert(exist(requiredFiles{n}, 'file') == 2, ['Missing expected validation artifact: ', requiredFiles{n}]);
    end
end

disp('test_09_preprocess_validation passed: preprocessing validation artifacts were generated.');

function safeName = makeSafeName(name)
safeName = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_|_$', '');
if isempty(safeName)
    safeName = 'sample';
end
end

function name = localEraseExtension(fileName)
[~, name, ~] = fileparts(fileName);
end
