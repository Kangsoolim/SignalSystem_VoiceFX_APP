%TEST_08_SAMPLE_BATCH_VALIDATION Validate batch processing of real sample wav files.
%   This test does not play audio, open App Designer, use realtime devices,
%   or require external dependencies.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplesDir = fullfile(projectRoot, 'samples');
sampleFiles = dir(fullfile(samplesDir, '*.wav'));
assert(~isempty(sampleFiles), 'samples/ must contain at least one .wav file.');

run(fullfile(projectRoot, 'scripts', 'run_sample_batch_validation.m'));

outputRoot = fullfile(projectRoot, 'results', 'sample_validation');
assert(exist(outputRoot, 'dir') == 7, 'results/sample_validation/ was not generated.');

batchSummaryPath = fullfile(outputRoot, 'batch_summary.csv');
assert(exist(batchSummaryPath, 'file') == 2, 'batch_summary.csv was not generated.');

summaryTable = readtable(batchSummaryPath, 'TextType', 'string');
assert(height(summaryTable) >= numel(sampleFiles), 'batch_summary.csv should include all scanned samples.');

for k = 1:numel(sampleFiles)
    [~, baseName] = fileparts(sampleFiles(k).name);
    safeName = makeSafeFolderNameForTest(baseName);
    sampleRoot = fullfile(outputRoot, safeName);
    audioDir = fullfile(sampleRoot, 'audio');
    summaryPath = fullfile(sampleRoot, 'summary.md');

    assert(exist(sampleRoot, 'dir') == 7, ['Missing per-sample output folder: ', sampleRoot]);
    assert(exist(audioDir, 'dir') == 7, ['Missing audio output folder: ', audioDir]);
    assert(exist(summaryPath, 'file') == 2, ['Missing summary.md: ', summaryPath]);

    originalPath = fullfile(audioDir, '00_original_preprocessed.wav');
    assert(exist(originalPath, 'file') == 2, ['Missing preprocessed original wav: ', originalPath]);
    originalInfo = audioinfo(originalPath);
    assert(originalInfo.TotalSamples > 0, ['Preprocessed original should contain samples: ', originalPath]);

    generatedWavs = dir(fullfile(audioDir, '*.wav'));
    assert(numel(generatedWavs) >= 8, ['Expected multiple function output wav files in: ', audioDir]);

    expectedAny = {
        'noise_white.wav';
        'filter_voice_enhance.wav';
        'voice_anonymous.wav';
        'fx_telephone.wav';
        'space_reverb.wav';
        'am_modulated.wav';
        'combo_anonymous_telephone_reverb.wav'
    };
    for n = 1:numel(expectedAny)
        assert(exist(fullfile(audioDir, expectedAny{n}), 'file') == 2, ...
            ['Missing expected validation output: ', expectedAny{n}]);
    end
end

disp('test_08_sample_batch_validation passed: real sample batch artifacts were generated.');

function safeName = makeSafeFolderNameForTest(baseName)
safeName = regexprep(baseName, '[''`]', '');
safeName = regexprep(safeName, '[^ -~]', '');
safeName = regexprep(safeName, '[^A-Za-z0-9_]+', '_');
safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_+|_+$', '');
if isempty(safeName)
    safeName = 'sample';
end
end
