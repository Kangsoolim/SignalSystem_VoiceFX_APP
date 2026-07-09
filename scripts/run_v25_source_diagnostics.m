function report = run_v25_source_diagnostics(inputArg)
%RUN_V25_SOURCE_DIAGNOSTICS Inspect one source and four adaptive mappings.
%   report = run_v25_source_diagnostics('voice.wav')
%   The filename may be located in the sibling Voice_test directory.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if nargin < 1 || isempty(inputArg)
    error('run_v25_source_diagnostics:MissingInput', ...
        'Provide a source filename or full path.');
end

inputPath = resolveVoiceTestInput(inputArg, projectRoot);
[xRaw, fs] = audioread(inputPath);
baseConfig = makeDefaultConfig();
x = preprocessAudio(xRaw, fs, baseConfig);
profile = analyzeVoiceProfile(x, fs);

if ~isfield(profile,'status') || ~strcmp(profile.status,'ok')
    error('run_v25_source_diagnostics:ProfileFailed', ...
        'The source does not contain enough voiced speech.');
end

styles = {'male_deep_gentle','female_gentle_sweet', ...
    'child_bright_soft','elder_warm_steady'};

report = struct();
report.inputPath = inputPath;
report.sampleRate = fs;
report.profile = profile;
report.styles = struct();

fprintf('Source: %s\n', inputPath);
fprintf('F0 median: %.2f Hz\n', profile.f0Median);
fprintf('Pitch range: %.2f st\n', profile.pitchRangeSemitones);
fprintf('Low-band ratio: %.3f\n', profile.lowBandEnergyRatio);

for k = 1:numel(styles)
    voiceConfig = baseConfig.voice;
    voiceConfig.enabled = true;
    voiceConfig.type = styles{k};
    voiceConfig.mode = styles{k};
    voiceConfig.intensity = 0.70;
    [adapted, diagnostics] = adaptVoiceStyleConfig(profile, voiceConfig);

    item = struct();
    item.pitchShiftSemitones = adapted.pitchShift;
    item.formantScale = adapted.params.formantScale;
    item.envelopeWarpStrength = adapted.params.envelopeWarpStrength;
    item.diagnostics = diagnostics;
    report.styles.(styles{k}) = item;

    fprintf('%s\n', styles{k});
    fprintf('  target F0 band: %.1f - %.1f Hz\n', ...
        diagnostics.targetF0Band(1), diagnostics.targetF0Band(2));
    fprintf('  planned output F0: %.2f Hz\n', diagnostics.recommendedOutputF0);
    fprintf('  prosody retention: %.3f\n', diagnostics.prosodyRetention);
    fprintf('  minimum style shift: %.2f st\n', ...
        diagnostics.minimumStyleShiftSemitones);
    fprintf('  style separation applied: %d\n', ...
        diagnostics.styleSeparationApplied);
    fprintf('  pitch shift: %.2f st\n', adapted.pitchShift);
    fprintf('  formant scale: %.3f\n', adapted.params.formantScale);
    fprintf('  envelope strength: %.3f\n', ...
        adapted.params.envelopeWarpStrength);
end
end
