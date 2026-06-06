%RUN_SAMPLE_BATCH_VALIDATION Batch-validate implemented file-mode effects on samples/*.wav.
%   This script scans samples/*.wav, writes per-sample audio/figure/summary
%   artifacts under results/sample_validation, and writes batch_summary.csv.
%   It does not play audio, open App Designer, or use realtime devices.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

maxDurationSeconds = 20;
samplesDir = fullfile(projectRoot, 'samples');
outputRoot = fullfile(projectRoot, 'results', 'sample_validation');
ensureDir(outputRoot);

sampleFiles = dir(fullfile(samplesDir, '*.wav'));
batchRows = cell(numel(sampleFiles), 9);
batchInfo = struct();
batchInfo.projectRoot = projectRoot;
batchInfo.samplesDir = samplesDir;
batchInfo.outputRoot = outputRoot;
batchInfo.maxDurationSeconds = maxDurationSeconds;
batchInfo.sampleFiles = {sampleFiles.name};
batchInfo.sampleResults = cell(numel(sampleFiles), 1);

fprintf('run_sample_batch_validation: found %d wav sample(s).\n', numel(sampleFiles));

for k = 1:numel(sampleFiles)
    inputPath = fullfile(sampleFiles(k).folder, sampleFiles(k).name);
    fprintf('Processing sample %d/%d: %s\n', k, numel(sampleFiles), sampleFiles(k).name);

    try
        result = processOneSample(inputPath, outputRoot, maxDurationSeconds, k);
    catch err
        result = makeFailedResult(inputPath, outputRoot, err);
    end

    batchInfo.sampleResults{k} = result;
    batchRows(k, :) = {
        result.inputFile, ...
        result.sampleRate, ...
        result.originalDurationSeconds, ...
        result.processedDurationSeconds, ...
        result.numAudioOutputs, ...
        result.numFigureOutputs, ...
        result.status, ...
        result.message, ...
        result.outputFolder ...
    };
end

batchTable = cell2table(batchRows, 'VariableNames', {
    'inputFile', ...
    'sampleRate', ...
    'originalDurationSeconds', ...
    'processedDurationSeconds', ...
    'numAudioOutputs', ...
    'numFigureOutputs', ...
    'status', ...
    'message', ...
    'outputFolder' ...
});
batchInfo.batchSummaryPath = fullfile(outputRoot, 'batch_summary.csv');
writetable(batchTable, batchInfo.batchSummaryPath);

fprintf('run_sample_batch_validation finished: %s\n', batchInfo.batchSummaryPath);

function result = processOneSample(inputPath, outputRoot, maxDurationSeconds, sampleIndex)
[xRaw, fs] = audioread(inputPath);
if isempty(fs) || fs <= 0
    error('runSampleBatch:InvalidSampleRate', 'Invalid sample rate.');
end

originalDurationSeconds = size(xRaw, 1) / fs;
maxSamples = max(1, round(maxDurationSeconds * fs));
if size(xRaw, 1) > maxSamples
    xRaw = xRaw(1:maxSamples, :);
end

baseConfig = makeValidationConfig();
x = preprocessAudio(xRaw, fs, baseConfig);
x = safeLimiter(x, baseConfig);
processedDurationSeconds = numel(x) / fs;

[~, baseName] = fileparts(inputPath);
safeName = makeSafeFolderName(baseName);
sampleRoot = fullfile(outputRoot, safeName);
audioDir = fullfile(sampleRoot, 'audio');
figureDir = fullfile(sampleRoot, 'figures');
ensureDir(sampleRoot);
ensureDir(audioDir);
ensureDir(figureDir);

audioOutputs = {};
figureOutputs = {};
failures = {};

audioOutputs{end + 1} = writeAudio(audioDir, '00_original_preprocessed.wav', x, fs, baseConfig); %#ok<AGROW>

noiseSpecs = {
    'noise_white.wav', 'white';
    'noise_hum50.wav', 'hum50';
    'noise_impulse.wav', 'impulse'
};
for n = 1:size(noiseSpecs, 1)
    cfg = baseConfig;
    cfg.noise.enabled = true;
    cfg.noise.type = noiseSpecs{n, 2};
    cfg.noise.snrDb = 15;
    cfg.noise.humAmplitude = 0.018;
    cfg.noise.impulseProbability = 0.0008;
    cfg.noise.noiseLevel = 0.25;
    cfg.noise.seed = 1000 + 31 * sampleIndex + n;
    [audioOutputs, failures] = runAndWrite(audioOutputs, failures, audioDir, noiseSpecs{n, 1}, x, fs, cfg);
end

filterSpecs = {
    'filter_highpass.wav', 'highpass';
    'filter_lowpass.wav', 'lowpass';
    'filter_bandpass.wav', 'bandpass';
    'filter_notch50.wav', 'notch50';
    'filter_voice_enhance.wav', 'voice_enhance'
};
for n = 1:size(filterSpecs, 1)
    cfg = baseConfig;
    cfg.filter.enabled = true;
    cfg.filter.type = filterSpecs{n, 2};
    cfg.filter.lowCutoff = 90;
    cfg.filter.highCutoff = min(4000, 0.45 * fs);
    cfg.filter.cutoff = [];
    cfg.filter.notchFreq = 50;
    cfg.filter.bandwidth = 2;
    cfg.filter.useZeroPhase = true;
    [audioOutputs, failures] = runAndWrite(audioOutputs, failures, audioDir, filterSpecs{n, 1}, x, fs, cfg);
end

voiceSpecs = {
    'voice_male.wav', 'male';
    'voice_female.wav', 'female';
    'voice_child.wav', 'child';
    'voice_elder.wav', 'elder';
    'voice_anonymous.wav', 'anonymous';
    'voice_robot_voice.wav', 'robot_voice'
};
voiceOutputs = struct();
for n = 1:size(voiceSpecs, 1)
    cfg = baseConfig;
    cfg.voice.enabled = true;
    cfg.voice.type = voiceSpecs{n, 2};
    cfg.voice.mix = 1.0;
    cfg.voice.intensity = 0.62;
    [audioOutputs, failures, y] = runAndWrite(audioOutputs, failures, audioDir, voiceSpecs{n, 1}, x, fs, cfg);
    voiceOutputs.(voiceSpecs{n, 2}) = y;
end

fxSpecs = {
    'fx_telephone.wav', 'telephone';
    'fx_walkie_talkie.wav', 'walkie_talkie';
    'fx_radio.wav', 'radio';
    'fx_lofi.wav', 'lofi';
    'fx_bitcrusher.wav', 'bitcrusher';
    'fx_robot.wav', 'robot'
};
fxOutputs = struct();
for n = 1:size(fxSpecs, 1)
    cfg = baseConfig;
    cfg.fx.enabled = true;
    cfg.fx.type = fxSpecs{n, 2};
    cfg.fx.mix = 1.0;
    cfg.fx.intensity = 0.62;
    cfg.fx.bitDepth = 8;
    cfg.fx.drive = 1.7;
    [audioOutputs, failures, y] = runAndWrite(audioOutputs, failures, audioDir, fxSpecs{n, 1}, x, fs, cfg);
    fxOutputs.(fxSpecs{n, 2}) = y;
end

spaceSpecs = {
    'space_delay.wav', 'delay';
    'space_reverb.wav', 'reverb';
    'space_bathroom.wav', 'bathroom';
    'space_cave.wav', 'cave';
    'space_stage.wav', 'stage'
};
spaceOutputs = struct();
for n = 1:size(spaceSpecs, 1)
    cfg = baseConfig;
    cfg.space.enabled = true;
    cfg.space.type = spaceSpecs{n, 2};
    cfg.space.mix = 0.38;
    cfg.space.delayTime = 0.20;
    cfg.space.feedback = 0.30;
    cfg.space.reverbAmount = 0.48;
    [audioOutputs, failures, y] = runAndWrite(audioOutputs, failures, audioDir, spaceSpecs{n, 1}, x, fs, cfg);
    spaceOutputs.(spaceSpecs{n, 2}) = y;
end

[audioOutputs, failures, amOutputs] = runAmOutputs(audioOutputs, failures, audioDir, x, fs, baseConfig);

comboSpecs = {
    'combo_anonymous_telephone_reverb.wav', 'anonymous', 'telephone', 'reverb';
    'combo_child_lofi_stage.wav', 'child', 'lofi', 'stage';
    'combo_robot_bitcrusher_delay.wav', 'robot_voice', 'bitcrusher', 'delay';
    'combo_elder_radio_cave.wav', 'elder', 'radio', 'cave';
    'combo_male_walkie_talkie_bathroom.wav', 'male', 'walkie_talkie', 'bathroom'
};
comboOutputs = struct();
for n = 1:size(comboSpecs, 1)
    cfg = baseConfig;
    cfg.voice.enabled = true;
    cfg.voice.type = comboSpecs{n, 2};
    cfg.voice.mix = 1.0;
    cfg.voice.intensity = 0.65;
    cfg.fx.enabled = true;
    cfg.fx.type = comboSpecs{n, 3};
    cfg.fx.mix = 0.90;
    cfg.fx.intensity = 0.58;
    cfg.space.enabled = true;
    cfg.space.type = comboSpecs{n, 4};
    cfg.space.mix = 0.34;
    cfg.space.delayTime = 0.16;
    cfg.space.feedback = 0.30;
    cfg.space.reverbAmount = 0.50;
    [audioOutputs, failures, y] = runAndWrite(audioOutputs, failures, audioDir, comboSpecs{n, 1}, x, fs, cfg);
    comboOutputs.(eraseExtension(comboSpecs{n, 1})) = y;
end

[figureOutputs, failures] = saveFigures(figureOutputs, failures, figureDir, x, fs, baseConfig.display, voiceOutputs, fxOutputs, spaceOutputs, comboOutputs, amOutputs);

status = 'completed';
message = 'ok';
if ~isempty(failures)
    status = 'completed_with_failures';
    message = strjoin(failures, ' | ');
end

summaryPath = fullfile(sampleRoot, 'summary.md');
writeSummary(summaryPath, inputPath, fs, originalDurationSeconds, processedDurationSeconds, audioOutputs, figureOutputs, failures);

result = struct();
result.inputFile = char(getFileName(inputPath));
result.sampleRate = fs;
result.originalDurationSeconds = originalDurationSeconds;
result.processedDurationSeconds = processedDurationSeconds;
result.numAudioOutputs = numel(audioOutputs);
result.numFigureOutputs = numel(figureOutputs);
result.status = status;
result.message = message;
result.outputFolder = sampleRoot;
result.audioOutputs = audioOutputs;
result.figureOutputs = figureOutputs;
result.failures = failures;
result.summaryPath = summaryPath;
end

function config = makeValidationConfig()
config = makeDefaultConfig();
config.audio.frameLength = 16384;
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.90;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
config.display.useDb = true;
config.display.dbFloor = -120;
config.display.maxDurationToPlot = 0.08;
end

function [audioOutputs, failures, y] = runAndWrite(audioOutputs, failures, audioDir, fileName, x, fs, config)
y = [];
try
    [y, ~] = processAudioFile(x, fs, config);
    audioOutputs{end + 1} = writeAudio(audioDir, fileName, y, fs, config); %#ok<AGROW>
catch err
    failures{end + 1} = [fileName, ': ', compactError(err)]; %#ok<AGROW>
end
end

function [audioOutputs, failures, amOutputs] = runAmOutputs(audioOutputs, failures, audioDir, x, fs, baseConfig)
amOutputs = struct('modulated', [], 'demodulated', []);
try
    carrierFreq = min(4000, 0.35 * fs);
    carrierFreq = min(carrierFreq, 0.90 * fs / 2);
    lowpassCutoff = min([3400, 0.35 * fs, 0.85 * fs / 2]);

    modConfig = baseConfig.modDemod;
    modConfig.enabled = true;
    modConfig.type = 'am_modulate';
    modConfig.carrierFreq = carrierFreq;
    modConfig.modulationIndex = 0.70;
    modConfig.messageScale = 0.80;
    [modulated, ~, ~] = applyModDemod(x, fs, modConfig, initProcessState(baseConfig));
    modulated = safeLimiter(modulated, baseConfig);
    audioOutputs{end + 1} = writeAudio(audioDir, 'am_modulated.wav', modulated, fs, baseConfig); %#ok<AGROW>

    demodConfig = baseConfig.modDemod;
    demodConfig.enabled = true;
    demodConfig.type = 'am_demodulate';
    demodConfig.carrierFreq = carrierFreq;
    demodConfig.lowpassCutoff = max(1, lowpassCutoff);
    demodConfig.useZeroPhase = true;
    [~, demodulated, ~] = applyModDemod(modulated, fs, demodConfig, initProcessState(baseConfig));
    demodulated = safeLimiter(demodulated, baseConfig);
    audioOutputs{end + 1} = writeAudio(audioDir, 'am_demodulated.wav', demodulated, fs, baseConfig); %#ok<AGROW>

    amOutputs.modulated = modulated;
    amOutputs.demodulated = demodulated;
catch err
    failures{end + 1} = ['am_modulated/am_demodulated: ', compactError(err)]; %#ok<AGROW>
end
end

function pathName = writeAudio(audioDir, fileName, x, fs, config)
pathName = fullfile(audioDir, fileName);
y = safeLimiter(x, config);
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98 * y / peak;
end
audiowrite(pathName, y, fs);
end

function [figureOutputs, failures] = saveFigures(figureOutputs, failures, figureDir, x, fs, displayConfig, voiceOutputs, fxOutputs, spaceOutputs, comboOutputs, amOutputs)
try
    figureOutputs{end + 1} = saveComparisonFigure( ...
        fullfile(figureDir, 'overview_voice_styles.png'), ...
        x, pickSignals(voiceOutputs, {'male', 'female', 'anonymous', 'robot_voice'}), ...
        {'Original', 'Male', 'Female', 'Anonymous', 'Robot Voice'}, fs, displayConfig, 0.08); %#ok<AGROW>
catch err
    failures{end + 1} = ['overview_voice_styles.png: ', compactError(err)]; %#ok<AGROW>
end

try
    figureOutputs{end + 1} = saveComparisonFigure( ...
        fullfile(figureDir, 'overview_vocal_fx.png'), ...
        x, pickSignals(fxOutputs, {'telephone', 'lofi', 'bitcrusher', 'robot'}), ...
        {'Original', 'Telephone', 'Lo-Fi', 'Bitcrusher', 'Robot'}, fs, displayConfig, 0.08); %#ok<AGROW>
catch err
    failures{end + 1} = ['overview_vocal_fx.png: ', compactError(err)]; %#ok<AGROW>
end

try
    figureOutputs{end + 1} = saveComparisonFigure( ...
        fullfile(figureDir, 'overview_space_fx.png'), ...
        x, pickSignals(spaceOutputs, {'delay', 'reverb', 'cave'}), ...
        {'Original', 'Delay', 'Reverb', 'Cave'}, fs, displayConfig, 0.35); %#ok<AGROW>
catch err
    failures{end + 1} = ['overview_space_fx.png: ', compactError(err)]; %#ok<AGROW>
end

try
    comboFields = fieldnames(comboOutputs);
    comboFields = comboFields(1:min(3, numel(comboFields)));
    figureOutputs{end + 1} = saveComparisonFigure( ...
        fullfile(figureDir, 'overview_combos.png'), ...
        x, pickSignals(comboOutputs, comboFields), ...
        makeComboFigureNames(comboFields), fs, displayConfig, 0.12); %#ok<AGROW>
catch err
    failures{end + 1} = ['overview_combos.png: ', compactError(err)]; %#ok<AGROW>
end

try
    amSignals = {amOutputs.modulated, amOutputs.demodulated};
    figureOutputs{end + 1} = saveComparisonFigure( ...
        fullfile(figureDir, 'overview_am_spectrum.png'), ...
        x, amSignals, {'Original', 'AM Modulated', 'AM Demodulated'}, fs, displayConfig, 0.02); %#ok<AGROW>
catch err
    failures{end + 1} = ['overview_am_spectrum.png: ', compactError(err)]; %#ok<AGROW>
end
end

function signals = pickSignals(s, names)
signals = cell(1, numel(names));
for k = 1:numel(names)
    if isfield(s, names{k})
        signals{k} = s.(names{k});
    else
        signals{k} = [];
    end
end
end

function names = makeComboFigureNames(comboFields)
names = cell(1, numel(comboFields) + 1);
names{1} = 'Original';
for k = 1:numel(comboFields)
    label = strrep(comboFields{k}, 'combo_', '');
    label = strrep(label, '_', ' ');
    names{k + 1} = label;
end
end

function pathName = saveComparisonFigure(pathName, original, effectSignals, names, fs, displayConfig, waveformSeconds)
signals = [{original}, effectSignals(:).'];
numRows = numel(signals);
fig = figure('Visible', 'off', 'Color', 'w', 'Name', getFileName(pathName), 'Position', [100, 100, 1200, max(720, 210 * numRows)]);

for k = 1:numRows
    y = signals{k};
    if isempty(y)
        y = zeros(size(original));
    end
    y = double(y(:));
    maxSamples = min(numel(y), max(1, round(waveformSeconds * fs)));
    t = (0:maxSamples-1).' / fs;

    subplot(numRows, 2, 2 * k - 1);
    plot(t, y(1:maxSamples), 'LineWidth', 0.8);
    grid on;
    title([names{k}, ' Waveform']);
    xlabel('Time (s)');
    ylabel('Amp');
    ylim([-1.05, 1.05]);

    subplot(numRows, 2, 2 * k);
    info = analyzeSpectrum(y, fs, displayConfig);
    plot(info.f, info.magDb, 'LineWidth', 0.8);
    grid on;
    title([names{k}, ' Spectrum']);
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (dB)');
    xlim([0, fs / 2]);
    ylim([displayConfig.dbFloor, 5]);
end

saveFigureFile(fig, pathName);
close(fig);
end

function saveFigureFile(fig, pathName)
try
    exportgraphics(fig, pathName, 'Resolution', 150);
catch
    print(fig, pathName, '-dpng', '-r150');
end
end

function writeSummary(pathName, inputPath, fs, originalDurationSeconds, processedDurationSeconds, audioOutputs, figureOutputs, failures)
fid = fopen(pathName, 'w');
if fid < 0
    error('runSampleBatch:SummaryOpenFailed', 'Could not open summary.md for writing.');
end
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, '# Sample Validation Summary\n\n');
fprintf(fid, '- Input file: `%s`\n', getFileName(inputPath));
fprintf(fid, '- Original sample rate: %g Hz\n', fs);
fprintf(fid, '- Original duration: %.3f seconds\n', originalDurationSeconds);
fprintf(fid, '- Processed duration: %.3f seconds\n\n', processedDurationSeconds);

fprintf(fid, '## Single-Function Audio Outputs\n\n');
singleOutputs = audioOutputs(~startsWithFileNames(audioOutputs, 'combo_'));
writePathList(fid, singleOutputs);

fprintf(fid, '\n## Combo Audio Outputs\n\n');
comboOutputs = audioOutputs(startsWithFileNames(audioOutputs, 'combo_'));
writePathList(fid, comboOutputs);

fprintf(fid, '\n## Figure Outputs\n\n');
writePathList(fid, figureOutputs);

fprintf(fid, '\n## Failures\n\n');
if isempty(failures)
    fprintf(fid, '- None\n');
else
    for k = 1:numel(failures)
        fprintf(fid, '- %s\n', failures{k});
    end
end

fprintf(fid, '\n## Notes\n\n');
fprintf(fid, '- Voice style effects are traditional signal-processing stylizations, not AI natural voice conversion.\n');
fprintf(fid, '- AM modulated audio is mainly intended for spectrum inspection; harsh listening quality is expected.\n');
end

function writePathList(fid, paths)
if isempty(paths)
    fprintf(fid, '- None\n');
    return;
end
for k = 1:numel(paths)
    fprintf(fid, '- `%s`\n', getFileName(paths{k}));
end
end

function mask = startsWithFileNames(paths, prefix)
mask = false(size(paths));
for k = 1:numel(paths)
    mask(k) = strncmp(getFileName(paths{k}), prefix, numel(prefix));
end
end

function result = makeFailedResult(inputPath, outputRoot, err)
[~, baseName] = fileparts(inputPath);
sampleRoot = fullfile(outputRoot, makeSafeFolderName(baseName));
ensureDir(sampleRoot);

result = struct();
result.inputFile = char(getFileName(inputPath));
result.sampleRate = NaN;
result.originalDurationSeconds = NaN;
result.processedDurationSeconds = NaN;
result.numAudioOutputs = 0;
result.numFigureOutputs = 0;
result.status = 'failed';
result.message = compactError(err);
result.outputFolder = sampleRoot;
result.audioOutputs = {};
result.figureOutputs = {};
result.failures = {result.message};
result.summaryPath = fullfile(sampleRoot, 'summary.md');

try
    writeSummary(result.summaryPath, inputPath, NaN, NaN, NaN, {}, {}, result.failures);
catch
end
end

function safeName = makeSafeFolderName(baseName)
safeName = regexprep(baseName, '[''`]', '');
safeName = regexprep(safeName, '[^ -~]', '');
safeName = regexprep(safeName, '[^A-Za-z0-9_]+', '_');
safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_+|_+$', '');
if isempty(safeName)
    safeName = 'sample';
end
end

function name = getFileName(pathName)
[~, stem, ext] = fileparts(pathName);
name = [stem, ext];
end

function stem = eraseExtension(fileName)
[~, stem] = fileparts(fileName);
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function text = compactError(err)
text = err.message;
text = strrep(text, sprintf('\n'), ' ');
text = strrep(text, sprintf('\r'), ' ');
text = strtrim(text);
end
