%TEST_12_ADAPTIVE_VOICE_STYLE Validate adaptive mapping inside voice style.
%
%   This test verifies:
%       1) lower and higher source voices receive different adaptive shifts;
%       2) the adaptive configuration is actually used by applyVoiceStyle;
%       3) frame-based file processing can calibrate across multiple frames;
%       4) outputs remain finite, length-preserving, and safe;
%       5) unvoiced/silent input falls back safely.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
duration = 1.6;
t = (0:1/fs:duration-1/fs).';

lowSource = makeSpeechLikeHarmonic(t, 110);
highSource = makeSpeechLikeHarmonic(t, 185);

config = makeDefaultConfig();
voiceConfig = config.voice;
voiceConfig.enabled = true;
voiceConfig.type = 'female';
voiceConfig.mode = 'female';
voiceConfig.mix = 1.0;
voiceConfig.intensity = 0.70;
voiceConfig.pitchShift = 0;
voiceConfig.params = struct( ...
    'adaptiveEnabled', true, ...
    'calibrationSeconds', 0.60, ...
    'adaptationStrength', 0.75);

[lowY, lowState] = applyVoiceStyle( ...
    lowSource, fs, voiceConfig, initProcessState(config));
[highY, highState] = applyVoiceStyle( ...
    highSource, fs, voiceConfig, initProcessState(config));

assertSafeOutput(lowY, lowSource, 'Low-source adaptive output');
assertSafeOutput(highY, highSource, 'High-source adaptive output');

assert(isfield(lowState.voice, 'sourceProfile'), ...
    'Adaptive path should store a source profile.');
assert(isfield(lowState.voice, 'adaptiveConfig'), ...
    'Adaptive path should store the mapped config.');
assert(isfield(lowState.voice, 'adaptiveDiagnostics'), ...
    'Adaptive path should store diagnostics.');
assert(startsWith(lowState.voice.calibrationStatus, 'ready'), ...
    'Low source should complete calibration.');
assert(startsWith(highState.voice.calibrationStatus, 'ready'), ...
    'High source should complete calibration.');

lowShift = lowState.voice.adaptiveConfig.pitchShift;
highShift = highState.voice.adaptiveConfig.pitchShift;

assert(isfinite(lowShift) && isfinite(highShift), ...
    'Adaptive pitch shifts must be finite.');
assert(lowShift > highShift + 0.25, ...
    'Lower source F0 should receive a larger upward female-style shift.');
assert(lowShift <= 12.01 && highShift <= 12.01, ...
    'Adaptive female pitch shifts must obey final preset safety bounds.');

% The two source profiles should reflect their intentionally different F0s.
assert(lowState.voice.sourceProfile.f0Median < ...
    highState.voice.sourceProfile.f0Median, ...
    'Source profile F0 ordering should match the synthetic signals.');

% Compare adaptive vs legacy path on the same low source.
legacyConfig = voiceConfig;
legacyConfig.params.adaptiveEnabled = false;
[legacyY, legacyState] = applyVoiceStyle( ...
    lowSource, fs, legacyConfig, initProcessState(config));

assertSafeOutput(legacyY, lowSource, 'Legacy output');
assert(strcmp(legacyState.voice.calibrationStatus, 'disabled'), ...
    'Legacy path should explicitly report disabled calibration.');
assert(norm(lowY - legacyY) / max(norm(lowSource), eps) > 1e-4, ...
    'Adaptive and legacy outputs should not be numerically identical.');

% Frame-based file path: calibration must accumulate across frames.
fileConfig = config;
fileConfig.audio.frameLength = 512;
fileConfig.voice = voiceConfig;
fileConfig.voice.params.calibrationSeconds = 0.50;
longSource = [lowSource; lowSource(1:round(0.8 * fs))];

[fileY, fileState] = processAudioFile(longSource, fs, fileConfig);
assertSafeOutput(fileY, longSource, 'Frame-based adaptive file output');
assert(isfield(fileState.voice, 'sourceProfile'), ...
    'Frame-based processing should calibrate across accumulated frames.');
assert(startsWith(fileState.voice.calibrationStatus, 'ready'), ...
    'Frame-based processing should reach ready calibration status.');
assert(fileState.voice.calibrationSamples >= ...
    fileState.voice.calibrationRequiredSamples, ...
    'Calibration buffer should reach the requested sample count.');

% Silence should never cause NaN/Inf or a crash.
silence = zeros(fs, 1);
[silenceY, silenceState] = applyVoiceStyle( ...
    silence, fs, voiceConfig, initProcessState(config));
assertSafeOutput(silenceY, silence, 'Silence fallback output');
assert(strcmp(silenceState.voice.calibrationStatus, 'retry_unvoiced') || ...
    strcmp(silenceState.voice.calibrationStatus, 'collecting'), ...
    'Silence should stay in a safe retry/collecting state.');

fprintf('Adaptive female shift: low source %.3f st, high source %.3f st.\n', ...
    lowShift, highShift);
disp('test_12_adaptive_voice_style passed: adaptive parameters drive voice transformation.');

function x = makeSpeechLikeHarmonic(t, f0)
% Make a deterministic speech-like voiced signal with mild prosody.
instantaneousF0 = f0 .* (1 + 0.025 * sin(2 * pi * 1.4 * t));
phase = cumsum(2 * pi * instantaneousF0 / 16000);
envelope = 0.58 + 0.24 * sin(2 * pi * 2.7 * t) .^ 2;

x = envelope .* ( ...
    0.30 * sin(phase) + ...
    0.16 * sin(2 * phase) + ...
    0.09 * sin(3 * phase) + ...
    0.04 * sin(5 * phase));

% Add deterministic formant-like spectral components.
x = x + 0.035 * sin(2 * pi * 780 * t) + ...
    0.020 * sin(2 * pi * 1450 * t);

% Two short pauses make activity detection less trivial.
fsLocal = 16000;
x(round(0.45 * fsLocal):round(0.52 * fsLocal)) = 0;
x(round(1.05 * fsLocal):round(1.13 * fsLocal)) = 0;

x = x(:);
peak = max(abs(x));
if peak > 0
    x = 0.65 * x / peak;
end
end

function assertSafeOutput(y, x, label)
assert(numel(y) == numel(x), [label, ' length must match input.']);
assert(isa(y, 'double'), [label, ' must be double.']);
assert(iscolumn(y), [label, ' must be a column vector.']);
assert(all(isfinite(y)), [label, ' must be finite.']);
assert(max(abs(y)) <= 1.000001, [label, ' must stay in safe range.']);
end
