function summary = run_v25_first_round_audition(inputArg)
%RUN_V25_FIRST_ROUND_AUDITION Generate four preserved style outputs.
%
%   The function name is kept for backward compatibility, but the current
%   implementation uses the naturalness-priority source-adaptive mapper and the
%   full-file quality chain for loaded WAV/M4A files.
%
%   Input may be either a full path or a filename located in the sibling
%   Voice_test folder. Example:
%       summary = run_v25_first_round_audition('zongcisheng.wav');
%
%   Generated audio is never overwritten. Output layout:
%       results/audio/by_source/<source>/four_style/<run_id>/

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if nargin < 1 || isempty(inputArg)
    inputPath = fullfile(projectRoot, 'samples', ...
        'spoken_monologue_Oscar Winning Tears.wav');
else
    inputPath = resolveVoiceTestInput(inputArg, projectRoot);
end

if exist(inputPath, 'file') ~= 2
    error('run_v25_first_round_audition:InputMissing', ...
        'Input audio not found: %s', inputPath);
end

[xRaw, fs] = audioread(inputPath);
inputConfig = makeDefaultConfig();
x = preprocessAudio(xRaw, fs, inputConfig);
profile = analyzeVoiceProfile(x, fs);
if ~isfield(profile, 'status') || ~strcmp(profile.status, 'ok')
    error('run_v25_first_round_audition:ProfileFailed', ...
        'The input does not contain enough voiced speech for calibration.');
end

styles = {'male_deep_gentle', 'female_gentle_sweet', ...
    'child_bright_soft', 'elder_warm_steady'};

[runDir, runId, sourceName] = createUniqueResultRun( ...
    projectRoot, inputPath, 'four_style');

summary = struct();
summary.inputPath = inputPath;
summary.sourceName = sourceName;
summary.sampleRate = fs;
summary.sourceProfile = profile;
summary.runId = runId;
summary.runDir = runDir;
summary.styles = struct();

fprintf('Source: %s\n', inputPath);
fprintf('Source F0 median: %.2f Hz\n', profile.f0Median);
fprintf('Output run: %s\n', runDir);

for k = 1:numel(styles)
    config = makeDefaultConfig();
    config.audio.frameLength = 1024;

    % All course modules remain independently switchable. Four-style
    % audition isolates the voice engine so the natural adaptive result is
    % not confounded by synthetic noise or denoising.
    config.noise.enabled = false;
    config.filter.enabled = false;
    config.fx.enabled = false;
    config.space.enabled = false;
    config.modDemod.enabled = false;

    config.voice.enabled = true;
    config.voice.type = styles{k};
    config.voice.mode = styles{k};
    config.voice.mix = 1.0;
    config.voice.intensity = 0.70;
    config.voice.params.sourceProfile = profile;

    % For loaded files, use the unified full-file chain. The user-facing
    % pipeline order and module switches are unchanged, while the voice stage
    % uses full-utterance pitch processing to avoid short-frame modulation
    % artifacts in large source-target conversions.
    [y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);

    outputName = sprintf('%s__%02d_%s.wav', ...
        sourceName, k, styles{k});
    outputPath = fullfile(runDir, outputName);
    audiowrite(outputPath, safeAudio(y), fs);

    item = struct();
    item.outputPath = outputPath;
    item.state = state;
    item.diagnostics = diagnostics;

    voiceDiag = diagnostics.voice;
    item.pitchShiftSemitones = getDiagField(voiceDiag, ...
        'pitchShiftSemitones', NaN);
    if isfield(voiceDiag, 'adaptive')
        item.sourcePitchBand = getDiagField(voiceDiag.adaptive, ...
            'sourcePitchBand', 'unknown');
        item.rawPitchShift = getDiagField(voiceDiag.adaptive, ...
            'rawPitchShift', NaN);
        item.residualPitchGapSemitones = getDiagField(voiceDiag.adaptive, ...
            'residualPitchGapSemitones', NaN);
        item.formantScale = getDiagField(voiceDiag.adaptive, ...
            'formantScale', NaN);
        item.envelopeWarpStrength = getDiagField(voiceDiag.adaptive, ...
            'envelopeWarpStrength', NaN);
        item.recommendedOutputF0 = getDiagField(voiceDiag.adaptive, ...
            'recommendedOutputF0', NaN);
        item.prosodyRetention = getDiagField(voiceDiag.adaptive, ...
            'prosodyRetention', NaN);
    else
        item.sourcePitchBand = 'unknown';
        item.rawPitchShift = NaN;
        item.residualPitchGapSemitones = NaN;
        item.formantScale = NaN;
        item.envelopeWarpStrength = NaN;
        item.recommendedOutputF0 = NaN;
        item.prosodyRetention = NaN;
    end

    summary.styles.(styles{k}) = item;

    fprintf('%s\n', styles{k});
    fprintf('  pitch shift: %.2f st\n', item.pitchShiftSemitones);
    fprintf('  formant scale: %.3f\n', item.formantScale);
    fprintf('  residual gap: %.2f st\n', item.residualPitchGapSemitones);
    fprintf('  planned output F0: %.2f Hz\n', item.recommendedOutputF0);
    fprintf('  prosody retention: %.3f\n', item.prosodyRetention);
    fprintf('  output: %s\n', outputPath);
end

fprintf('Four-style audition finished. No previous run was overwritten.\n');
end

function value = getDiagField(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
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
