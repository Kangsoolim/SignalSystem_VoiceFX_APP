function exportInfo = export_stage3_noise_filter_examples()
%EXPORT_STAGE3_NOISE_FILTER_EXAMPLES Export focused Stage 3 noise/filter assets.
%   Generates a compact set of wav files and figures under
%   results/stage3_noise_filter without clearing or rebuilding other
%   project results.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2-1/fs).';
original = makeSpeechLikeSignal(t);
filterInput = safeLimiter(original + 0.055 * sin(2 * pi * 50 * t) + ...
    0.035 * sin(2 * pi * 6500 * t) + 0.015 * randn(size(t)), makeDefaultConfig());

outputRoot = fullfile(projectRoot, 'results', 'stage3_noise_filter');
audioDir = fullfile(outputRoot, 'audio');
figureDir = fullfile(outputRoot, 'figures');
responseDir = fullfile(outputRoot, 'filter_response');
ensureDir(audioDir);
ensureDir(figureDir);
ensureDir(responseDir);

config = makeDefaultConfig();
config.audio.frameLength = 2048;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];

exportInfo = struct();
exportInfo.outputRoot = outputRoot;
exportInfo.audio = {};
exportInfo.figures = {};
exportInfo.filterResponses = {};
exportInfo.hiddenModes = {};

exportInfo.audio{end + 1} = writeAudio(audioDir, 'stage3_original.wav', original, fs, config);
exportInfo.audio{end + 1} = writeAudio(audioDir, 'stage3_filter_input_hum_hiss.wav', filterInput, fs, config);

noiseModes = {'white', 'hum50', 'impulse'};
for k = 1:numel(noiseModes)
    cfg = config;
    cfg.noise.enabled = true;
    cfg.noise.type = noiseModes{k};
    cfg.noise.seed = 7300 + k;
    cfg.noise.snrDb = 16;
    cfg.noise.humAmplitude = 0.045;
    cfg.noise.humHarmonicRatio = 0.40;
    cfg.noise.impulseProbability = 0.002;
    cfg.noise.noiseLevel = 0.18;

    [y, ~] = processAudioFile(original, fs, cfg);
    audioPath = writeAudio(audioDir, sprintf('stage3_noise_%s.wav', noiseModes{k}), y, fs, config);
    figurePath = saveSignalFigure(figureDir, sprintf('stage3_noise_%s_wave_spectrum.png', noiseModes{k}), ...
        original, y, fs, config.display);

    exportInfo.audio{end + 1} = audioPath; %#ok<AGROW>
    exportInfo.figures{end + 1} = figurePath; %#ok<AGROW>
end

filterModes = {'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};
for k = 1:numel(filterModes)
    cfg = config;
    cfg.filter.enabled = true;
    cfg.filter.type = filterModes{k};
    cfg.filter.order = 3;
    cfg.filter.cutoff = [];
    cfg.filter.lowCutoff = 120;
    cfg.filter.highCutoff = 3600;
    cfg.filter.notchFreq = 50;
    cfg.filter.bandwidth = 5;
    cfg.filter.useZeroPhase = false;

    if strcmp(filterModes{k}, 'highpass')
        cfg.filter.lowCutoff = 140;
    elseif strcmp(filterModes{k}, 'lowpass')
        cfg.filter.highCutoff = 3000;
    elseif strcmp(filterModes{k}, 'bandpass')
        cfg.filter.lowCutoff = 140;
        cfg.filter.highCutoff = 3200;
    elseif strcmp(filterModes{k}, 'voice_enhance')
        cfg.filter.lowCutoff = 120;
        cfg.filter.highCutoff = 3600;
    end

    [y, ~] = processAudioFile(filterInput, fs, cfg);
    audioPath = writeAudio(audioDir, sprintf('stage3_filter_%s.wav', filterModes{k}), y, fs, config);
    figurePath = saveSignalFigure(figureDir, sprintf('stage3_filter_%s_wave_spectrum.png', filterModes{k}), ...
        filterInput, y, fs, config.display);
    responsePath = saveFilterResponse(responseDir, sprintf('stage3_response_%s.png', filterModes{k}), fs, cfg.filter, config.display);

    exportInfo.audio{end + 1} = audioPath; %#ok<AGROW>
    exportInfo.figures{end + 1} = figurePath; %#ok<AGROW>
    exportInfo.filterResponses{end + 1} = responsePath; %#ok<AGROW>
end

summaryPath = fullfile(outputRoot, 'stage3_summary.txt');
writeSummary(summaryPath, exportInfo, noiseModes, filterModes);
exportInfo.summaryPath = summaryPath;

disp('export_stage3_noise_filter_examples finished:');
disp(outputRoot);
end

function x = makeSpeechLikeSignal(t)
f0 = 145 + 22 * sin(2 * pi * 0.9 * t) + 5 * sin(2 * pi * 2.4 * t);
phase = cumsum(2 * pi * f0 / 16000);
env = 0.32 + 0.58 * (sin(2 * pi * 1.7 * t) .^ 2);
vowels = sin(phase) + 0.45 * sin(2 * phase) + 0.20 * sin(3 * phase);
formants = 0.14 * sin(2 * pi * 650 * t) + ...
    0.10 * sin(2 * pi * 1250 * t) + ...
    0.05 * sin(2 * pi * 2500 * t);
x = env .* (0.34 * vowels + formants);
x = x(:);
x = 0.72 * x / max(max(abs(x)), eps);
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

function figurePath = saveSignalFigure(figureDir, fileName, x, y, fs, displayConfig)
plotConfig = displayConfig;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = figureDir;
plotConfig.figureName = fileName;
plotConfig.useDb = true;
plotConfig.dbFloor = -115;
plotConfig.maxDurationToPlot = 0.18;
info = plotSignalInfo(x, y, fs, plotConfig);
figurePath = info.figurePath;
end

function responsePath = saveFilterResponse(responseDir, fileName, fs, filterConfig, displayConfig)
plotConfig = displayConfig;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = responseDir;
plotConfig.figureName = fileName;
plotConfig.responseFftLength = 4096;
info = plotFilterResponse(fs, filterConfig, plotConfig);
responsePath = info.figurePath;
end

function writeSummary(pathName, exportInfo, noiseModes, filterModes)
fid = fopen(pathName, 'w');
if fid < 0
    error('exportStage3:SummaryOpenFailed', 'Could not open summary file.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'Stage 3 noise/filter export\n');
fprintf(fid, 'Noise modes: %s\n', strjoin(noiseModes, ', '));
fprintf(fid, 'Filter modes: %s\n', strjoin(filterModes, ', '));
fprintf(fid, 'Hidden modes: none\n\n');

fprintf(fid, 'Audio files:\n');
writeList(fid, exportInfo.audio, exportInfo.outputRoot);
fprintf(fid, '\nWaveform/spectrum figures:\n');
writeList(fid, exportInfo.figures, exportInfo.outputRoot);
fprintf(fid, '\nFilter response figures:\n');
writeList(fid, exportInfo.filterResponses, exportInfo.outputRoot);
end

function writeList(fid, paths, outputRoot)
for k = 1:numel(paths)
    fprintf(fid, '- %s\n', makeRelativePath(paths{k}, outputRoot));
end
end

function relPath = makeRelativePath(pathName, outputRoot)
prefix = [outputRoot, filesep];
if strncmp(pathName, prefix, numel(prefix))
    relPath = pathName(numel(prefix) + 1:end);
else
    [~, stem, ext] = fileparts(pathName);
    relPath = [stem, ext];
end
relPath = strrep(relPath, filesep, '/');
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end
