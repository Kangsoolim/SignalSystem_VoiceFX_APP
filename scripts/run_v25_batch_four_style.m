function batch = run_v25_batch_four_style()
%RUN_V25_BATCH_FOUR_STYLE Process every supported source in sibling Voice_test.
%   batch = run_v25_batch_four_style()
%
%   Input folder:
%       <parent of project>/Voice_test/
%
%   Supported extensions:
%       .wav .m4a .mp3 .flac
%
%   Each source is processed independently by run_v25_first_round_audition.
%   Results are preserved under:
%       results/audio/by_source/<source>/four_style/<run_id>/
%
%   A failure in one file is recorded and does not erase earlier outputs.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

voiceTestDir = fullfile(fileparts(projectRoot), 'Voice_test');
if exist(voiceTestDir, 'dir') ~= 7
    error('run_v25_batch_four_style:VoiceTestMissing', ...
        'Voice_test folder not found: %s', voiceTestDir);
end

extensions = {'*.wav','*.m4a','*.mp3','*.flac'};
files = struct([]);
for k = 1:numel(extensions)
    files = [files; dir(fullfile(voiceTestDir, extensions{k}))]; %#ok<AGROW>
end

if isempty(files)
    error('run_v25_batch_four_style:NoAudio', ...
        'No supported audio files found in: %s', voiceTestDir);
end

% Stable alphabetical order makes batch reports repeatable.
[~, order] = sort(lower({files.name}));
files = files(order);

batch = struct();
batch.voiceTestDir = voiceTestDir;
batch.fileCount = numel(files);
batch.items = cell(numel(files),1);
batch.successCount = 0;
batch.failureCount = 0;

fprintf('Batch four-style conversion: %d source file(s)\n', numel(files));
for k = 1:numel(files)
    inputPath = fullfile(files(k).folder, files(k).name);
    fprintf('\n[%d/%d] %s\n', k, numel(files), files(k).name);

    item = struct();
    item.inputPath = inputPath;
    item.status = 'failed';
    item.message = '';
    item.summary = [];

    try
        item.summary = run_v25_first_round_audition(inputPath);
        item.status = 'ok';
        item.message = 'completed';
        batch.successCount = batch.successCount + 1;
    catch errorInfo
        item.message = errorInfo.message;
        batch.failureCount = batch.failureCount + 1;
        warning('run_v25_batch_four_style:FileFailed', ...
            'Failed for %s: %s', files(k).name, errorInfo.message);
    end

    batch.items{k} = item;
end

fprintf('\nBatch finished: %d succeeded, %d failed.\n', ...
    batch.successCount, batch.failureCount);
end
