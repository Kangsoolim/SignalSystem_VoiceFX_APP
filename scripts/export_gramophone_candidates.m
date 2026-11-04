function exportInfo = export_gramophone_candidates(includeRejectedCandidates)
%EXPORT_GRAMOPHONE_CANDIDATES Export the official gramophone FX result.
%   The final gramophone preset uses the horn audition recipe selected by
%   listening review. gramophone_horn remains an internal alias only.

if nargin < 1 || isempty(includeRejectedCandidates)
    includeRejectedCandidates = false;
end
if includeRejectedCandidates
    error('exportGramophoneCandidates:RejectedDisabled', ...
        'Rejected gramophone candidates are deprecated and are not exported by default.');
end

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplesDir = fullfile(projectRoot, 'samples');
audioDir = fullfile(projectRoot, 'results', 'audio', 'final_fx', 'gramophone');
figureDir = fullfile(projectRoot, 'results', 'figures', 'final_fx', 'gramophone');
summaryDir = fullfile(projectRoot, 'results', 'final_fx', 'gramophone');
ensureDir(audioDir);
ensureDir(figureDir);
ensureDir(summaryDir);

config = makeAuditionConfig();
officialMode = config.fx.gramophoneOfficialPreset;
assert(strcmp(officialMode, 'gramophone'), 'Official gramophone mode must be gramophone.');
assert(~any(ismember(config.fx.deprecatedPresets, config.fx.gramophoneCandidatePresets)), ...
    'Deprecated gramophone variants must not be in the export list.');

samplePaths = pickRepresentativeSamples(samplesDir, 4);

exportInfo = struct();
exportInfo.audioDir = audioDir;
exportInfo.figureDir = figureDir;
exportInfo.summaryPath = fullfile(summaryDir, 'gramophone_official_summary.txt');
exportInfo.samplePaths = samplePaths;
exportInfo.officialMode = officialMode;
exportInfo.wavFiles = {};
exportInfo.figureFiles = {};

fid = fopen(exportInfo.summaryPath, 'w');
if fid < 0
    error('exportGramophoneCandidates:SummaryOpenFailed', 'Could not open summary file.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'Official gramophone export\n');
fprintf(fid, 'Mode: %s\n', officialMode);
fprintf(fid, 'Display name: %s\n', config.fx.presets.gramophone.displayName);
fprintf(fid, 'Internal alias: gramophone_horn\n');
fprintf(fid, 'Audio directory: %s\n', makeRelativePath(audioDir, projectRoot));
fprintf(fid, 'Figure directory: %s\n\n', makeRelativePath(figureDir, projectRoot));

for s = 1:numel(samplePaths)
    samplePath = samplePaths{s};
    [xRaw, fs] = audioread(samplePath);
    x = preprocessAudio(xRaw, fs, config);
    x = limitDuration(x, fs, 4.0);
    x = safeLimiter(x, config);
    y = processOfficialGramophone(x, fs, config);

    sampleSlug = makeSlug(samplePath);
    fileStem = sprintf('gramophone_official_%s', sampleSlug);
    wavPath = writeAudio(audioDir, [fileStem, '.wav'], y, fs, config);
    waveformPath = saveWaveformFigure(figureDir, [fileStem, '_waveform.png'], x, y, fs);
    spectrumPath = saveSpectrumFigure(figureDir, [fileStem, '_spectrum.png'], x, y, fs);
    spectrogramPath = saveSpectrogramFigure(figureDir, [fileStem, '_spectrogram.png'], x, y, fs, config);

    exportInfo.wavFiles{end + 1} = wavPath; %#ok<AGROW>
    exportInfo.figureFiles{end + 1} = waveformPath; %#ok<AGROW>
    exportInfo.figureFiles{end + 1} = spectrumPath; %#ok<AGROW>
    exportInfo.figureFiles{end + 1} = spectrogramPath; %#ok<AGROW>

    metrics = makeMetricsRow(x, y, fs);
    fprintf(fid, '[sample_%02d]\n', s);
    fprintf(fid, 'Source: %s\n', makeRelativePath(samplePath, projectRoot));
    fprintf(fid, 'Wav: %s\n', makeRelativePath(wavPath, projectRoot));
    fprintf(fid, 'Waveform: %s\n', makeRelativePath(waveformPath, projectRoot));
    fprintf(fid, 'Spectrum: %s\n', makeRelativePath(spectrumPath, projectRoot));
    fprintf(fid, 'Spectrogram: %s\n', makeRelativePath(spectrogramPath, projectRoot));
    fprintf(fid, 'Metrics: diffRmsRatio=%.4f centroidHz=%.1f pass120_4500=%.4f highGt6000=%.4f peak=%.4f\n\n', ...
        metrics.diffRmsRatio, metrics.centroidHz, metrics.pass120_4500, ...
        metrics.highGt6000, metrics.peak);
end

disp('export_gramophone_candidates finished:');
disp(audioDir);
disp(figureDir);
disp(exportInfo.summaryPath);
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

function y = processOfficialGramophone(x, fs, config)
processConfig = config;
processConfig.audio.removeDC = false;
processConfig.audio.normalizeInput = false;
processConfig.fx.enabled = true;
processConfig.fx.type = config.fx.gramophoneOfficialPreset;
processConfig.fx.mode = 'none';
[y, ~] = processAudioFile(x, fs, processConfig);
y = safeLimiter(y, config);
end

function samplePaths = pickRepresentativeSamples(samplesDir, maxCount)
files = dir(fullfile(samplesDir, '*.wav'));
if isempty(files)
    error('exportGramophoneCandidates:NoSamples', 'No wav files found under samples/.');
end
preferredTokens = {'demo_speech', 'demo_speech_alt'};
chosen = false(size(files));
samplePaths = {};
for k = 1:numel(preferredTokens)
    token = preferredTokens{k};
    matchIndex = [];
    for n = 1:numel(files)
        if ~chosen(n) && ~isempty(strfind(lower(files(n).name), token)) %#ok<STREMP>
            matchIndex = n;
            break;
        end
    end
    if ~isempty(matchIndex)
        chosen(matchIndex) = true;
        samplePaths{end + 1} = fullfile(files(matchIndex).folder, files(matchIndex).name); %#ok<AGROW>
    end
end
for k = 1:numel(files)
    if numel(samplePaths) >= maxCount
        break;
    end
    if ~chosen(k)
        samplePaths{end + 1} = fullfile(files(k).folder, files(k).name); %#ok<AGROW>
    end
end
samplePaths = samplePaths(1:min(maxCount, numel(samplePaths)));
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

function pathName = saveWaveformFigure(figureDir, fileName, x, y, fs)
pathName = fullfile(figureDir, fileName);
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Gramophone Waveform');
set(fig, 'Position', [100, 100, 1000, 420]);
plotCount = min([numel(x), numel(y), round(0.30 * fs)]);
t = (0:plotCount-1).' / fs;
plot(t, x(1:plotCount), 'Color', [0.1, 0.35, 0.75]);
hold on;
plot(t, y(1:plotCount), 'Color', [0.75, 0.2, 0.12]);
grid on;
xlabel('Time (s)');
ylabel('Amplitude');
title('Official Gramophone Waveform');
legend({'Input', 'Gramophone'}, 'Location', 'best');
saveFigure(fig, pathName, 150);
close(fig);
end

function pathName = saveSpectrumFigure(figureDir, fileName, x, y, fs)
pathName = fullfile(figureDir, fileName);
[fx, xDb] = spectrumDb(x, fs);
[fy, yDb] = spectrumDb(y, fs);
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Gramophone Spectrum');
set(fig, 'Position', [100, 100, 1000, 420]);
plot(fx, xDb, 'Color', [0.1, 0.35, 0.75]);
hold on;
plot(fy, yDb, 'Color', [0.75, 0.2, 0.12]);
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title('Official Gramophone Spectrum');
legend({'Input', 'Gramophone'}, 'Location', 'best');
xlim([0, min(fs / 2, 10000)]);
saveFigure(fig, pathName, 150);
close(fig);
end

function pathName = saveSpectrogramFigure(figureDir, fileName, x, y, fs, config)
plotConfig = config.display;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = figureDir;
plotConfig.figureName = fileName;
plotConfig.spectrogramWindowLength = 512;
plotConfig.spectrogramOverlapLength = 384;
plotConfig.spectrogramFftLength = 1024;
plotInfo = plotSpectrogramInfo(x, y, fs, plotConfig);
pathName = plotInfo.figurePath;
end

function [freq, magDb] = spectrumDb(x, fs)
x = double(x(:));
n = max(1, numel(x));
window = 0.5 - 0.5 * cos(2 * pi * (0:n-1).' / max(n - 1, 1));
spec = abs(fft(x .* window));
count = floor(n / 2) + 1;
freq = (0:count-1).' * fs / n;
mag = spec(1:count) / max(sum(window), eps);
magDb = 20 * log10(max(mag, 1e-8));
end

function slug = makeSlug(pathName)
[~, stem] = fileparts(pathName);
slug = regexprep(stem, '[^A-Za-z0-9]+', '_');
slug = regexprep(slug, '^_+|_+$', '');
if isempty(slug)
    slug = 'sample';
end
end

function row = makeMetricsRow(x, y, fs)
row = struct();
row.diffRmsRatio = rmsValue(y - x) / max(rmsValue(x), eps);
row.centroidHz = spectralCentroid(y, fs);
row.pass120_4500 = bandFraction(y, fs, 120, 4500);
row.highGt6000 = bandFraction(y, fs, 6000, fs / 2);
row.peak = max(abs(y));
end

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end

function value = spectralCentroid(x, fs)
[freq, mag2] = powerSpectrum(x, fs);
value = sum(freq .* mag2) / max(sum(mag2), eps);
end

function value = bandFraction(x, fs, lowCutoff, highCutoff)
[freq, mag2] = powerSpectrum(x, fs);
mask = freq >= lowCutoff & freq <= highCutoff;
value = sum(mag2(mask)) / max(sum(mag2), eps);
end

function [freq, mag2] = powerSpectrum(x, fs)
x = double(x(:));
n = numel(x);
spec = abs(fft(x));
count = floor(n / 2) + 1;
freq = (0:count-1).' * fs / n;
mag2 = spec(1:count) .^ 2;
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

function saveFigure(fig, pathName, resolution)
if exist('exportgraphics', 'file') == 2
    exportgraphics(fig, pathName, 'Resolution', resolution);
else
    saveas(fig, pathName);
end
end
