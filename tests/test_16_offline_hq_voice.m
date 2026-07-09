%TEST_16_OFFLINE_HQ_VOICE Validate full-utterance high-quality voice path.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.5-1/fs).';
f0 = 135 + 9*sin(2*pi*0.8*t);
phase = cumsum(2*pi*f0/fs);
x = 0.32*sin(phase) + 0.15*sin(2*phase) + 0.07*sin(3*phase);
x = 0.6*x/max(abs(x));

config = makeDefaultConfig();
config.filter.enabled = true;
config.filter.type = 'speech_clean';
config.filter.mode = 'speech_clean';
config.voice.enabled = true;
config.voice.type = 'female';
config.voice.mode = 'female';
config.voice.intensity = 0.62;
config.voice.pitchShift = 0;

[y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);

assert(numel(y) == numel(x), 'HQ output length must equal input length.');
assert(iscolumn(y), 'HQ output must be a column vector.');
assert(all(isfinite(y)), 'HQ output must contain only finite samples.');
assert(max(abs(y)) <= config.output.peakLimit + 1e-6, ...
    'HQ output must respect configured peak limit.');
assert(isstruct(state), 'State output must be a struct.');
assert(strcmp(diagnostics.status, 'ok'), 'HQ diagnostics status must be ok.');
assert(isfield(diagnostics.voice, 'adaptive'), ...
    'HQ diagnostics must include adaptive mapping information.');

disp('test_16_offline_hq_voice passed: full-utterance HQ path is numerically safe.');
