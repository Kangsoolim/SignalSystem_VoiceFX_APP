function exportInfo = export_stage5_space_validation()
%EXPORT_STAGE5_SPACE_VALIDATION Export M07 space preset audition assets.
%   Generates representative wav, waveform/spectrum figures, spectrograms,
%   and a concise summary under results/stage5_space_validation. The script
%   only exercises the space module and shared file pipeline.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

outputRoot = fullfile(projectRoot, 'results', 'stage5_space_validation');
audioDir = fullfile(outputRoot, 'wav');
figureDir = fullfile(outputRoot, 'figures');
ensureDir(outputRoot);
ensureDir(audioDir);
ensureDir(figureDir);
removeStaleSpaceArtifacts(audioDir, figureDir);

[x, fs, inputName] = loadValidationInput(projectRoot);
config = makeValidationConfig();
x = preprocessAudio(x, fs, config);
x = safeLimiter(x, config);

modes = {'delay', 'bathroom', 'cave'};
exportInfo = struct();
exportInfo.projectRoot = projectRoot;
exportInfo.outputRoot = outputRoot;
exportInfo.inputName = inputName;
exportInfo.sampleRate = fs;
exportInfo.audio = {};
exportInfo.figures = {};
exportInfo.metrics = struct();

exportInfo.audio{end + 1} = writeAudio(audioDir, '00_original_preprocessed.wav', x, fs, config);

summaryRows = cell(numel(modes), 9);
for k = 1:numel(modes)
    modeName = modes{k};
    cfg = config;
    cfg.space.enabled = true;
    cfg.space.type = modeName;

    [y, ~] = processAudioFile(x, fs, cfg);
    y = safeLimiter(y, config);

    audioPath = writeAudio(audioDir, sprintf('space_%s.wav', modeName), y, fs, config);
    exportInfo.audio{end + 1} = audioPath; %#ok<AGROW>

    figConfig = config.display;
    figConfig.enabled = true;
    figConfig.saveFigure = true;
    figConfig.outputDir = figureDir;
    figConfig.useDb = true;
    figConfig.maxDurationToPlot = min(1.2, numel(x) / fs);

    figConfig.figureName = sprintf('space_%s_waveform_spectrum.png', modeName);
    waveInfo = plotSignalInfo(x, y, fs, figConfig);
    exportInfo.figures{end + 1} = waveInfo.figurePath; %#ok<AGROW>

    figConfig.figureName = sprintf('space_%s_spectrogram.png', modeName);
    specInfo = plotSpectrogramInfo(x, y, fs, figConfig);
    exportInfo.figures{end + 1} = specInfo.figurePath; %#ok<AGROW>

    metric = measureSpaceOutput(x, y, fs);
    exportInfo.metrics.(modeName) = metric;
    preset = config.space.presets.(modeName);
    summaryRows(k, :) = {modeName, preset.mix, preset.feedback, preset.reverbAmount, getPresetField(preset, 'wetGain', 1.0), metric.peak, metric.rmsRatio, metric.diffRmsRatio, preset.showInApp};
end

exportInfo.summaryPath = fullfile(outputRoot, 'stage5_space_summary.md');
writeSummary(exportInfo.summaryPath, exportInfo, summaryRows, config.space);

disp('export_stage5_space_validation finished:');
disp(exportInfo.outputRoot);
end

function removeStaleSpaceArtifacts(audioDir, figureDir)
staleFiles = {
    fullfile(audioDir, 'space_reverb.wav');
    fullfile(audioDir, 'space_stage.wav');
    fullfile(figureDir, 'space_reverb_waveform_spectrum.png');
    fullfile(figureDir, 'space_reverb_spectrogram.png');
    fullfile(figureDir, 'space_stage_waveform_spectrum.png');
    fullfile(figureDir, 'space_stage_spectrogram.png')
};
for k = 1:numel(staleFiles)
    if exist(staleFiles{k}, 'file') == 2
        delete(staleFiles{k});
    end
end
end
function config = makeValidationConfig()
config = makeDefaultConfig();
config.audio.frameLength = 2048;
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.86;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
config.output.limiterMode = 'soft';
config.display.useDb = true;
config.display.dbFloor = -120;
config.display.maxDurationToPlot = 1.2;
end

function [x, fs, inputName] = loadValidationInput(projectRoot)
samplesDir = fullfile(projectRoot, 'samples');
preferred = fullfile(samplesDir, 'demo_speech.wav');
if exist(preferred, 'file') == 2
    [x, fs] = audioread(preferred);
    inputName = 'demo_speech.wav';
else
    files = dir(fullfile(samplesDir, '*.wav'));
    if ~isempty(files)
        inputPath = fullfile(files(1).folder, files(1).name);
        [x, fs] = audioread(inputPath);
        inputName = files(1).name;
    else
        fs = 16000;
        t = (0:1/fs:4-1/fs).';
        x = 0.30 * sin(2 * pi * 180 * t) + 0.14 * sin(2 * pi * 540 * t) + 0.06 * sin(2 * pi * 1600 * t);
        x = x .* (0.85 + 0.15 * sin(2 * pi * 2.4 * t));
        inputName = 'synthetic_voice_like_tone';
    end
end

if size(x, 2) > 1
    x = mean(x, 2);
end
maxSamples = min(numel(x), round(8 * fs));
x = x(1:maxSamples);
end

function metric = measureSpaceOutput(x, y, fs)
x = double(x(:));
y = double(y(:));
metric = struct();
metric.peak = max(abs(y));
metric.rms = rmsLocal(y);
metric.inputRms = max(rmsLocal(x), eps);
metric.rmsRatio = metric.rms / metric.inputRms;
metric.diffRmsRatio = rmsLocal(y - x) / metric.inputRms;
lastCount = min(numel(y), max(1, round(0.50 * fs)));
metric.tailRms = rmsLocal(y(end - lastCount + 1:end));
metric.finite = all(isfinite(y));
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

function value = getPresetField(preset, fieldName, defaultValue)
if isfield(preset, fieldName) && ~isempty(preset.(fieldName))
    value = preset.(fieldName);
else
    value = defaultValue;
end
end
function writeSummary(pathName, exportInfo, rows, spaceConfig)
fid = fopen(pathName, 'w');
if fid < 0
    error('exportStage5Space:SummaryOpenFailed', 'Could not open summary file.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, '# Stage 5 Space Validation Summary\n\n');
fprintf(fid, '- Input: `%s`\n', exportInfo.inputName);
fprintf(fid, '- Sample rate: %g Hz\n', exportInfo.sampleRate);
fprintf(fid, '- Output root: `%s`\n\n', exportInfo.outputRoot);

fprintf(fid, '## Preset Screening\n\n');
fprintf(fid, '| Preset | Mix | Feedback | Reverb amount | Wet gain | Peak | RMS ratio | Diff RMS ratio | Show in app |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---|\n');
for k = 1:size(rows, 1)
    fprintf(fid, '| %s | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f | %s |\n', ...
        rows{k, 1}, rows{k, 2}, rows{k, 3}, rows{k, 4}, rows{k, 5}, rows{k, 6}, rows{k, 7}, rows{k, 8}, logicalText(rows{k, 9}));
end

fprintf(fid, '\n## Recommendation\n\n');
fprintf(fid, '- Keep/display: `%s`\n', strjoin(spaceConfig.displayPresets, '`, `'));
fprintf(fid, '- Hide by default: `%s`\n', strjoin(spaceConfig.hiddenPresets, '`, `'));
fprintf(fid, '- Realtime trial priority: delay, bathroom. Cave remains a file-mode audition candidate.\n');

fprintf(fid, '\n## Audio Outputs\n\n');
writePathList(fid, exportInfo.audio);
fprintf(fid, '\n## Figure Outputs\n\n');
writePathList(fid, exportInfo.figures);
end

function writePathList(fid, paths)
for k = 1:numel(paths)
    fprintf(fid, '- `%s`\n', paths{k});
end
end

function text = logicalText(value)
if value
    text = 'yes';
else
    text = 'no';
end
end

function value = rmsLocal(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end
