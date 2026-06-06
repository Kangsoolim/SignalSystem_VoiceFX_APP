%TEST_00_FRAMEWORK_SMOKE Minimal framework smoke test.
% This test verifies interfaces only. It does not validate audio algorithms.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1-1/fs).';
x = 0.2 * sin(2 * pi * 440 * t);

config = makeDefaultConfig();
state0 = initProcessState(config);
[y, state] = processAudioFile(x, fs, config);

assert(isstruct(state0), 'initProcessState must return a struct.');
assert(isstruct(state), 'processAudioFile must return a state struct.');
assert(numel(y) == numel(x), 'Output length must match input length.');
assert(isa(y, 'double'), 'Output must be double.');
assert(iscolumn(y), 'Output must be a column vector.');
assert(all(isfinite(y)), 'Output must not contain NaN or Inf.');
assert(max(abs(y)) <= 1.000001, 'Output should stay within [-1, 1].');

disp('test_00_framework_smoke passed: framework interfaces are callable.');
