%TEST_18_CALIBRATION_RECOVERY Ensure silence-first sessions can recalibrate.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
silence = zeros(fs,1);
t = (0:1/fs:2.0-1/fs).';
f0 = 150 + 8*sin(2*pi*0.7*t);
phase = cumsum(2*pi*f0/fs);
speechLike = 0.28*sin(phase) + 0.12*sin(2*phase) + 0.05*sin(3*phase);
x = [silence; speechLike];

config = makeDefaultConfig();
config.audio.frameLength = 512;
config.voice.enabled = true;
config.voice.type = 'female';
config.voice.mode = 'female';
config.voice.params.calibrationSeconds = 0.60;

[y, state] = processAudioFile(x, fs, config);

assert(numel(y) == numel(x), 'Recovery output length mismatch.');
assert(all(isfinite(y)), 'Recovery output contains nonfinite samples.');
assert(startsWith(state.voice.calibrationStatus, 'ready'), ...
    'Voice calibration should recover after an initial silent segment.');
assert(isfield(state.voice, 'sourceProfile'), ...
    'Recovered calibration should store a source profile.');

disp('test_18_calibration_recovery passed: silence-first calibration recovers when speech arrives.');
