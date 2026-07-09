function info = run_adaptive_voice_audition(inputPath, voiceMode)
%RUN_ADAPTIVE_VOICE_AUDITION Export clean/realtime/HQ voice comparisons.
%
% Example:
%   info = run_adaptive_voice_audition([], 'female');
%
% Outputs are written to results/audio/adaptive_voice_v5/.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if nargin < 1 || isempty(inputPath)
    inputPath = fullfile(projectRoot, 'samples', ...
        'spoken_monologue_Oscar Winning Tears.wav');
end
if nargin < 2 || isempty(voiceMode)
    voiceMode = 'female';
end
if exist(inputPath, 'file') ~= 2
    error('Input audio file not found: %s', inputPath);
end

[x, fs] = audioread(inputPath);
baseConfig = makeDefaultConfig();
x = preprocessAudio(x, fs, baseConfig);
sourceProfile = analyzeVoiceProfile(x, fs);

% Clean-only reference.
cleanConfig = makeDefaultConfig();
cleanConfig.audio.frameLength = 1024;
cleanConfig.filter.enabled = true;
cleanConfig.filter.type = 'speech_clean';
cleanConfig.filter.mode = 'speech_clean';
cleanConfig.output.limiterMode = 'soft';

cleanTic = tic;
[cleanY, ~] = processAudioFile(x, fs, cleanConfig);
cleanSeconds = toc(cleanTic);

% Realtime-compatible stateful DSP path.
voiceConfig = cleanConfig;
voiceConfig.voice.enabled = true;
voiceConfig.voice.type = voiceMode;
voiceConfig.voice.mode = voiceMode;
voiceConfig.voice.mix = 1.0;
voiceConfig.voice.intensity = 0.62;
voiceConfig.voice.pitchShift = 0;
voiceConfig.voice.params.sourceProfile = sourceProfile;
voiceConfig.voice.params.adaptiveEnabled = true;
voiceConfig.voice.params.adaptationStrength = 0.62;

realtimeTic = tic;
[realtimeY, realtimeState] = processAudioFile(x, fs, voiceConfig);
realtimeSeconds = toc(realtimeTic);

% High-quality full-file path. This is the preferred engine for uploaded
% files and export when shiftPitch with phase locking/formant preservation
% is available.
hqTic = tic;
[hqY, hqState, hqDiagnostics] = ...
    processAudioFileHighQuality(x, fs, voiceConfig);
hqSeconds = toc(hqTic);

outputDir = fullfile(projectRoot, 'results', 'audio', 'adaptive_voice_v5');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
baseName = safeName(voiceMode);

originalPath = fullfile(outputDir, [baseName, '_00_original.wav']);
cleanPath = fullfile(outputDir, [baseName, '_01_speech_clean.wav']);
realtimePath = fullfile(outputDir, [baseName, '_02_realtime_dsp.wav']);
hqPath = fullfile(outputDir, [baseName, '_03_offline_hq.wav']);

audiowrite(originalPath, safeAudio(x), fs);
audiowrite(cleanPath, safeAudio(cleanY), fs);
audiowrite(realtimePath, safeAudio(realtimeY), fs);
audiowrite(hqPath, safeAudio(hqY), fs);

info = struct();
info.inputPath = inputPath;
info.voiceMode = voiceMode;
info.sampleRate = fs;
info.durationSeconds = numel(x)/fs;
info.originalPath = originalPath;
info.cleanPath = cleanPath;
info.realtimePath = realtimePath;
info.hqPath = hqPath;
info.cleanProcessingSeconds = cleanSeconds;
info.realtimeProcessingSeconds = realtimeSeconds;
info.hqProcessingSeconds = hqSeconds;
info.realtimeRTF = realtimeSeconds/max(info.durationSeconds, eps);
info.hqRTF = hqSeconds/max(info.durationSeconds, eps);
info.sourceProfile = sourceProfile;
info.realtimeState = realtimeState;
info.hqState = hqState;
info.hqDiagnostics = hqDiagnostics;

fprintf('Audition export complete:\n');
fprintf('  Original : %s\n', originalPath);
fprintf('  Cleaned  : %s\n', cleanPath);
fprintf('  Realtime : %s\n', realtimePath);
fprintf('  OfflineHQ: %s\n', hqPath);
fprintf('  Realtime-compatible DSP RTF: %.3f\n', info.realtimeRTF);
fprintf('  Offline HQ RTF             : %.3f\n', info.hqRTF);
if isfield(hqDiagnostics, 'voice') && ...
        isfield(hqDiagnostics.voice, 'adaptive') && ...
        isfield(hqDiagnostics.voice.adaptive, 'recommendedPitchShift')
    fprintf('  Recommended pitch shift    : %.2f semitones\n', ...
        hqDiagnostics.voice.adaptive.recommendedPitchShift);
end
end

function y = safeAudio(x)
y = double(x(:));
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98*y/peak;
end
end

function name = safeName(value)
name = lower(char(value));
name(~isstrprop(name, 'alphanum')) = '_';
end
