%TEST_13B_PITCH_INDEX_WRAP Stress circular pitch-buffer indexing.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
duration = 4.0;
t = (0:1/fs:duration-1/fs).';
f0 = 135 + 18 * sin(2*pi*0.55*t);
phase = cumsum(2*pi*f0/fs);
x = 0.30*sin(phase) + 0.14*sin(2*phase) + 0.06*sin(3*phase);
x = x(:);

config = makeDefaultConfig();
config.audio.frameLength = 257;
config.voice.enabled = true;
config.voice.type = 'female';
config.voice.mode = 'female';
config.voice.mix = 1.0;
config.voice.intensity = 0.65;
profile = analyzeVoiceProfile(x, fs);
config.voice.params.sourceProfile = profile;
config.voice.params.adaptiveEnabled = true;

[y, state] = processAudioFile(x, fs, config);

assert(numel(y) == numel(x), 'Output length must equal input length.');
assert(all(isfinite(y)), 'Output must contain only finite values.');
assert(max(abs(y)) <= 1.000001, 'Output must remain in safe range.');
assert(isfield(state.voice, 'pitchBuffer'), 'Pitch buffer state must persist.');
assert(isfinite(state.voice.pitchPhase), 'Pitch phase must remain finite.');
assert(state.voice.pitchWriteIndex >= 1, 'Write index must be >= 1.');
assert(state.voice.pitchWriteIndex <= numel(state.voice.pitchBuffer), ...
    'Write index must remain inside circular buffer.');

disp('test_13b_pitch_index_wrap passed: circular pitch indexing is safe.');
