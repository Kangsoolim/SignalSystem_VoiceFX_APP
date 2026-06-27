function exportInfo = export_stage4_fx_audition()
%EXPORT_STAGE4_FX_AUDITION Export curated M06 FX examples on a real sample.
%   Creates representative wav files plus waveform/spectrum comparison PNGs
%   under results/stage4_fx_audition. This script does not touch App or
%   realtime code.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplesDir = fullfile(projectRoot, 'samples');
outputRoot = fullfile(projectRoot, 'results', 'stage4_fx_audition_curated_v3');
wavDir = fullfile(outputRoot, 'wav');
figureDir = fullfile(outputRoot, 'figures');
ensureDir(outputRoot);
ensureDir(wavDir);
ensureDir(figureDir);

config = makeAuditionConfig();
samplePath = pickRealSample(samplesDir);
[xRaw, fs] = audioread(samplePath);
x = preprocessAudio(xRaw, fs, config);
x = limitDuration(x, fs, 5.0);
x = safeLimiter(x, config);

fxModes = {'telephone', 'radio', 'bitcrusher', 'gramophone', 'robot'};
clipOrder = [{'original'}, fxModes];

exportInfo = struct();
exportInfo.outputRoot = outputRoot;
exportInfo.samplePath = samplePath;
exportInfo.wavFiles = {};
exportInfo.figureFiles = {};
exportInfo.auditionFile = fullfile(outputRoot, 'stage4_fx_audition_all.wav');
exportInfo.summaryPath = fullfile(outputRoot, 'stage4_fx_summary.txt');

outputs = struct();
outputs.original = x;
exportInfo.wavFiles{end + 1} = writeAudio(wavDir, '00_original_preprocessed.wav', x, fs, config);

plotConfig = config.display;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = figureDir;
plotConfig.useDb = true;
plotConfig.maxDurationToPlot = 0.18;

for k = 1:numel(fxModes)
    mode = fxModes{k};
    fxConfig = config.fx;
    fxConfig.enabled = true;
    fxConfig.type = mode;

    [y, ~] = processAudioFile(x, fs, setFxConfig(config, fxConfig));
    outputs.(mode) = y;

    wavName = sprintf('%02d_%s.wav', k, mode);
    exportInfo.wavFiles{end + 1} = writeAudio(wavDir, wavName, y, fs, config); %#ok<AGROW>

    plotConfig.figureName = sprintf('%02d_%s_waveform_spectrum.png', k, mode);
    plotInfo = plotSignalInfo(x, y, fs, plotConfig);
    if plotInfo.figureSaved
        exportInfo.figureFiles{end + 1} = plotInfo.figurePath; %#ok<AGROW>
    end
end

montage = buildMontage(outputs, clipOrder, fs, 16000);
audiowrite(exportInfo.auditionFile, safeLimiter(montage, config), 16000);
writeSummary(exportInfo.summaryPath, config.fx, fxModes, samplePath, exportInfo, projectRoot, outputRoot);

disp('export_stage4_fx_audition finished:');
disp(outputRoot);
disp(exportInfo.auditionFile);
end

function config = makeAuditionConfig()
config = makeDefaultConfig();
config.audio.frameLength = 2048;
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.82;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
config.display.dbFloor = -120;
end

function config = setFxConfig(config, fxConfig)
config.fx = fxConfig;
end

function samplePath = pickRealSample(samplesDir)
preferred = dir(fullfile(samplesDir, '*upbeat*.wav'));
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*spoken*.wav'));
end
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*.wav'));
end
if isempty(preferred)
    error('exportStage4FxAudition:NoSamples', 'No wav files found under samples/.');
end
samplePath = fullfile(preferred(1).folder, preferred(1).name);
end

function y = limitDuration(x, fs, maxSeconds)
x = x(:);
y = x(1:min(numel(x), max(1, round(maxSeconds * fs))));
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

function montage = buildMontage(outputs, clipOrder, fs, montageFs)
longGap = zeros(round(0.55 * montageFs), 1);
shortGap = zeros(round(0.30 * montageFs), 1);
montage = zeros(0, 1);
for k = 1:numel(clipOrder)
    clip = outputs.(clipOrder{k});
    clip = limitDuration(clip, fs, 2.8);
    clip = resampleLinear(clip, fs, montageFs);
    clip = fadeEdges(clip, montageFs);
    montage = [montage; longGap; makeCue(k, montageFs); shortGap; clip]; %#ok<AGROW>
end
end

function cue = makeCue(index, fs)
freq = 560 + 70 * index;
t = (0:max(1, round(0.10 * fs))-1).' / fs;
cue = 0.18 * sin(2 * pi * freq * t);
cue = fadeEdges(cue, fs);
end

function y = resampleLinear(x, fsIn, fsOut)
x = double(x(:));
if fsIn == fsOut || isempty(x)
    y = x;
    return;
end
duration = (numel(x) - 1) / fsIn;
tIn = linspace(0, duration, numel(x)).';
tOut = (0:max(1, round(duration * fsOut))).' / fsOut;
y = interp1(tIn, x, tOut, 'linear', 'extrap');
y = y(:);
end

function y = fadeEdges(x, fs)
y = double(x(:));
fadeSamples = min(round(0.015 * fs), floor(numel(y) / 2));
if fadeSamples <= 1
    return;
end
fade = linspace(0, 1, fadeSamples).';
y(1:fadeSamples) = y(1:fadeSamples) .* fade;
y(end-fadeSamples+1:end) = y(end-fadeSamples+1:end) .* flipud(fade);
end

function writeSummary(pathName, fxConfig, fxModes, samplePath, exportInfo, projectRoot, outputRoot)
fid = fopen(pathName, 'w');
if fid < 0
    error('exportStage4FxAudition:SummaryOpenFailed', 'Could not open summary file.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'Stage 4 M06 FX audition export\n');
fprintf(fid, 'Sample: %s\n', makeRelativePath(samplePath, projectRoot));
fprintf(fid, 'Audition montage: %s\n\n', makeRelativePath(exportInfo.auditionFile, outputRoot));

fprintf(fid, 'Recommended display presets:\n');
for k = 1:numel(fxConfig.displayPresets)
    mode = fxConfig.displayPresets{k};
    if isfield(fxConfig.presets, mode)
        fprintf(fid, '- %s: %s\n', mode, fxConfig.presets.(mode).displayName);
    else
        fprintf(fid, '- %s: deprecated/hidden\n', mode);
    end
end

fprintf(fid, '\nRecommended hidden/heavy presets:\n');
for k = 1:numel(fxConfig.hiddenPresets)
    mode = fxConfig.hiddenPresets{k};
    if isfield(fxConfig.presets, mode)
        fprintf(fid, '- %s: %s\n', mode, fxConfig.presets.(mode).displayName);
    else
        fprintf(fid, '- %s: deprecated/hidden\n', mode);
    end
end

fprintf(fid, '\nPreset parameters:\n');
for k = 1:numel(fxModes)
    mode = fxModes{k};
    fprintf(fid, '\n[%s]\n', mode);
    writeStructFields(fid, fxConfig.presets.(mode));
end

fprintf(fid, '\nWav files:\n');
for k = 1:numel(exportInfo.wavFiles)
    fprintf(fid, '- %s\n', makeRelativePath(exportInfo.wavFiles{k}, outputRoot));
end

fprintf(fid, '\nFigures:\n');
for k = 1:numel(exportInfo.figureFiles)
    fprintf(fid, '- %s\n', makeRelativePath(exportInfo.figureFiles{k}, outputRoot));
end
end

function writeStructFields(fid, value)
names = fieldnames(value);
for k = 1:numel(names)
    name = names{k};
    item = value.(name);
    if islogical(item)
        text = mat2str(item);
    elseif isnumeric(item)
        text = mat2str(item);
    else
        text = char(item);
    end
    fprintf(fid, '%s = %s\n', name, text);
end
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function relPath = makeRelativePath(pathName, rootPath)
prefix = [rootPath, filesep];
if strncmp(pathName, prefix, numel(prefix))
    relPath = pathName(numel(prefix) + 1:end);
else
    [~, stem, ext] = fileparts(pathName);
    relPath = [stem, ext];
end
relPath = strrep(relPath, filesep, '/');
end
