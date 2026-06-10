function exportInfo = export_visualization_examples()
%EXPORT_VISUALIZATION_EXAMPLES Export a small M09 visualization image set.
%   This script only creates Stage 2 report figures. It does not clear or
%   batch-regenerate results, and it does not modify any audio algorithms.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2-1/fs).';
original = makeSpeechLikeSignal(t, fs);

config = makeDefaultConfig();
stage2Dir = fullfile(projectRoot, 'results', 'figures', 'stage2_visualization');
ensureDir(stage2Dir);

filterConfig = config;
filterConfig.filter.enabled = true;
filterConfig.filter.type = 'voice_enhance';
filterConfig.filter.order = 4;
filterConfig.filter.lowCutoff = 90;
filterConfig.filter.highCutoff = 3600;
filterConfig.filter.useZeroPhase = false;
[processed, processState] = processAudioFile(original, fs, filterConfig);

displayConfig = config.display;
displayConfig.enabled = true;
displayConfig.saveFigure = true;
displayConfig.outputDir = stage2Dir;
displayConfig.dbFloor = -110;
displayConfig.spectrogramWindowLength = 512;
displayConfig.spectrogramOverlapLength = 384;
displayConfig.spectrogramFftLength = 1024;

spectrogramConfig = displayConfig;
spectrogramConfig.figureName = 'm09_spectrogram_original_vs_voice_enhance.png';
spectrogramInfo = plotSpectrogramInfo(original, processed, fs, spectrogramConfig);

filterModes = {'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};
filterResponseInfos = cell(size(filterModes));
for k = 1:numel(filterModes)
    oneFilterConfig = config.filter;
    oneFilterConfig.enabled = true;
    oneFilterConfig.type = filterModes{k};
    oneFilterConfig.order = 4;
    oneFilterConfig.lowCutoff = 80;
    oneFilterConfig.highCutoff = 3400;
    oneFilterConfig.notchFreq = 50;
    oneFilterConfig.bandwidth = 2;
    oneFilterConfig.useZeroPhase = false;

    if strcmp(filterModes{k}, 'voice_enhance')
        oneFilterConfig.highCutoff = 4000;
    end

    responseConfig = displayConfig;
    responseConfig.figureName = sprintf('m09_filter_response_%s.png', filterModes{k});
    filterResponseInfos{k} = plotFilterResponse(fs, oneFilterConfig, responseConfig);
end

exportInfo = struct();
exportInfo.fs = fs;
exportInfo.outputDir = stage2Dir;
exportInfo.spectrogram = spectrogramInfo.figurePath;
exportInfo.filterResponses = collectFigurePaths(filterResponseInfos);
exportInfo.processState = processState;
exportInfo.designNote = 'Filter response coefficients are rebuilt from the same parameter rules used by applyDenoiseFilter private helpers.';

disp('export_visualization_examples finished. Generated figures:');
disp(exportInfo.spectrogram);
for k = 1:numel(exportInfo.filterResponses)
    disp(exportInfo.filterResponses{k});
end
end

function x = makeSpeechLikeSignal(t, fs)
f0 = 150 + 24 * sin(2 * pi * 1.0 * t) + 7 * sin(2 * pi * 2.6 * t);
phase = cumsum(2 * pi * f0 / fs);
env = 0.35 + 0.55 * (sin(2 * pi * 1.8 * t) .^ 2);
vowel = sin(phase) + 0.45 * sin(2 * phase) + 0.22 * sin(3 * phase);
formants = 0.14 * sin(2 * pi * 650 * t) + ...
    0.10 * sin(2 * pi * 1200 * t) + ...
    0.06 * sin(2 * pi * 2500 * t);
fricative = 0.018 * sin(2 * pi * 5200 * t) .* (sin(2 * pi * 3.1 * t) > 0);
x = env .* (0.34 * vowel + formants) + fricative;
x = x(:);
x(~isfinite(x)) = 0;
x = 0.75 * x / max(max(abs(x)), eps);
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function paths = collectFigurePaths(infoCells)
paths = cell(size(infoCells));
for k = 1:numel(infoCells)
    paths{k} = infoCells{k}.figurePath;
end
end
