%TEST_10_RUN_FILE_MODE Validate VoiceFX App file-mode backend entry point.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplePath = pickSample(fullfile(projectRoot, 'samples'));
outputDir = fullfile(projectRoot, 'results', 'app_test');
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end

cases = {
    'none', struct('noise', 'none', 'filter', 'none', 'voice', 'none', 'fx', 'none', 'space', 'none', 'am', 'off')
    'telephone', struct('filter', 'voice_enhance', 'fx', 'telephone', 'am', 'off')
    'robot', struct('voice', 'robot', 'fx', 'robot', 'am', 'off')
    'lofi', struct('filter', 'lowpass', 'fx', 'lofi', 'am', 'off')
    'delay', struct('space', 'delay', 'am', 'off')
    'am_modulate', struct('filter', 'voice_enhance', 'am', 'modulate')
};

for k = 1:size(cases, 1)
    caseName = cases{k, 1};
    selections = cases{k, 2};
    config = makeAppConfig(selections);
    outputPath = fullfile(outputDir, ['test_10_', caseName, '.wav']);
    result = runFileMode(samplePath, config, 'OutputPath', outputPath, 'Overwrite', true);

    assert(isstruct(result), 'runFileMode must return a struct.');
    assert(strcmp(result.inputPath, samplePath), 'Result inputPath should match the requested sample.');
    assert(result.fs > 0, 'Sample rate must be positive.');
    assert(isfield(result, 'xOriginal') && ~isempty(result.xOriginal), 'xOriginal must be returned.');
    assert(isfield(result, 'xProcessedInput') && ~isempty(result.xProcessedInput), 'xProcessedInput must be returned.');
    assert(isfield(result, 'y') && ~isempty(result.y), 'Processed output must be returned.');
    assert(iscolumn(result.xProcessedInput) && iscolumn(result.y), 'Audio vectors must be columns.');
    assert(abs(numel(result.y) - numel(result.xProcessedInput)) <= 1, 'Output length should match processed input length.');
    assert(all(isfinite(result.xProcessedInput)) && all(isfinite(result.y)), 'Audio output must not contain NaN or Inf.');
    assert(max(abs(result.y)) <= 1.000001, 'Processed output must stay in safe amplitude range.');
    assert(result.duration > 0, 'Duration must be positive.');
    assert(exist(outputPath, 'file') == 2, 'Output wav should be written under results/app_test.');

    info = audioinfo(outputPath);
    assert(info.TotalSamples > 0, 'Written wav must contain samples.');
end

try
    runFileMode(fullfile(projectRoot, 'samples', 'missing_file.wav'), makeDefaultConfig());
    error('test_10_run_file_mode:ExpectedMissingFileError', 'Missing file should throw.');
catch ME
    assert(contains(ME.identifier, 'FileNotFound'), 'Missing file should report FileNotFound.');
end

disp('test_10_run_file_mode passed: file-mode backend is stable for App presets.');

function samplePath = pickSample(samplesDir)
files = dir(fullfile(samplesDir, '*.wav'));
assert(~isempty(files), 'At least one wav sample is required under samples/.');
spoken = dir(fullfile(samplesDir, '*spoken*.wav'));
if ~isempty(spoken)
    files = spoken;
end
samplePath = fullfile(files(1).folder, files(1).name);
end

