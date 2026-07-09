%TEST_23_RESULT_RUN_PRESERVATION Ensure result runs never overwrite.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

tempRoot = fullfile(tempdir, 'voicefx_result_run_test');
if exist(tempRoot, 'dir') == 7
    rmdir(tempRoot, 's');
end
mkdir(tempRoot);
cleanupObj = onCleanup(@() cleanupFolder(tempRoot)); %#ok<NASGU>

fakeInput = fullfile(tempRoot, 'zongcisheng.wav');
[runDir1, runId1, source1] = createUniqueResultRun( ...
    tempRoot, fakeInput, 'four_style');
[runDir2, runId2, source2] = createUniqueResultRun( ...
    tempRoot, fakeInput, 'four_style');

assert(exist(runDir1, 'dir') == 7, 'First run directory must exist.');
assert(exist(runDir2, 'dir') == 7, 'Second run directory must exist.');
assert(~strcmp(runDir1, runDir2), ...
    'Repeated runs must use different result directories.');
assert(~strcmp(runId1, runId2), ...
    'Repeated runs must use different run IDs.');
assert(strcmp(source1, 'zongcisheng') && strcmp(source2, 'zongcisheng'), ...
    'Source basename must be preserved in result organization.');
assert(contains(runDir1, 'zongcisheng'), ...
    'Result path must be organized by source basename.');

disp('test_23_result_run_preservation passed: repeated runs are preserved and source-organized.');

function cleanupFolder(pathValue)
if exist(pathValue, 'dir') == 7
    rmdir(pathValue, 's');
end
end
