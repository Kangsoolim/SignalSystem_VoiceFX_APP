%TEST_13_VOICE_CONTINUITY Check frame-boundary continuity of voice core.
%
% This is a numerical continuity regression test, not a perceptual MOS test.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
duration = 3.0;
t = (0:1/fs:duration-1/fs).';

f0 = 145;
phase = cumsum(2*pi*(f0 .* (1 + 0.03*sin(2*pi*1.1*t))) / fs);
envelope = 0.55 + 0.30 * sin(2*pi*2.6*t).^2;
x = envelope .* ( ...
    0.35*sin(phase) + ...
    0.15*sin(2*phase) + ...
    0.07*sin(3*phase));
x = 0.5 * x / max(abs(x));

config = makeDefaultConfig();
config.audio.frameLength = 512;
config.voice.enabled = true;
config.voice.type = 'female';
config.voice.mode = 'female';
config.voice.mix = 1.0;
config.voice.intensity = 0.65;

profile = analyzeVoiceProfile(x, fs);
config.voice.params = struct( ...
    'adaptiveEnabled', true, ...
    'adaptationStrength', 0.65, ...
    'sourceProfile', profile, ...
    'pitchMaxDelayMs', 45);

[y, state] = processAudioFile(x, fs, config);

assert(numel(y) == numel(x), 'Output length must match input.');
assert(all(isfinite(y)), 'Output must be finite.');
assert(max(abs(y)) <= 1.000001, 'Output must stay in safe range.');
assert(isfield(state.voice, 'pitchPhase'), ...
    'Stateful pitch shifter state should persist.');

frameLength = config.audio.frameLength;
boundaries = frameLength:frameLength:(numel(y)-1);

allJumps = abs(diff(y));
boundaryJumps = abs(y(boundaries+1) - y(boundaries));

referenceJump = median(allJumps) + eps;
ratio = median(boundaryJumps) / referenceJump;

% A loose guard against catastrophic per-frame reset clicks. Natural
% waveform boundaries can still have larger-than-median sample differences.
assert(ratio < 12, ...
    'Frame-boundary jumps are excessively larger than normal sample jumps.');

fprintf('Median boundary-jump ratio: %.3f\n', ratio);
disp('test_13_voice_continuity passed: no catastrophic frame-reset discontinuity detected.');
