function metrics = analyze_stage4_fx_metrics()
%ANALYZE_STAGE4_FX_METRICS Compute comparison metrics for curated M06 FX.
%   The report helps tune Stage 4 presets against real samples without
%   relying only on waveform screenshots.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeAnalysisConfig();
samplePath = pickRealSample(fullfile(projectRoot, 'samples'));
[xRaw, fs] = audioread(samplePath);
x = preprocessAudio(xRaw, fs, config);
x = limitDuration(x, fs, 4.0);
x = safeLimiter(x, config);

fxModes = {'telephone', 'radio', 'bitcrusher', 'gramophone', 'robot'};
metrics = struct();
metrics.samplePath = samplePath;
metrics.fs = fs;
metrics.rows = cell(numel(fxModes), 10);

outputRoot = fullfile(projectRoot, 'results', 'stage4_fx_audition_curated_v3');
ensureDir(outputRoot);
reportPath = fullfile(outputRoot, 'stage4_fx_metrics.txt');
fid = fopen(reportPath, 'w');
if fid < 0
    error('analyzeStage4FxMetrics:ReportOpenFailed', 'Could not open metrics report.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'Stage 4 M06 FX metrics\n');
fprintf(fid, 'Sample: %s\n\n', makeRelativePath(samplePath, projectRoot));
fprintf(fid, ['mode\tdiffRmsRatio\tcentroidHz\tlowLt300\ttele300_3400\twalkie380_3000\t', ...
    'radio170_4700\thighGt6000\tzcrRatio\tpeak\n']);

for k = 1:numel(fxModes)
    mode = fxModes{k};
    fxConfig = config.fx;
    fxConfig.enabled = true;
    fxConfig.type = mode;

    [y, ~] = applyVocalFX(x, fs, fxConfig, initProcessState(config));
    row = makeMetricsRow(mode, x, y, fs);
    metrics.rows(k, :) = row;

    fprintf(fid, '%s\t%.4f\t%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n', ...
        row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, row{7}, row{8}, row{9}, row{10});
end

metrics.reportPath = reportPath;
disp('analyze_stage4_fx_metrics finished:');
disp(reportPath);
end

function config = makeAnalysisConfig()
config = makeDefaultConfig();
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.82;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
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
    error('analyzeStage4FxMetrics:NoSamples', 'No wav files found under samples/.');
end
samplePath = fullfile(preferred(1).folder, preferred(1).name);
end

function row = makeMetricsRow(mode, x, y, fs)
diffRmsRatio = rmsValue(y - x) / max(rmsValue(x), eps);
centroidHz = spectralCentroid(y, fs);
lowLt300 = bandFraction(y, fs, 0, 300);
teleBand = bandFraction(y, fs, 300, 3400);
walkieBand = bandFraction(y, fs, 380, 3000);
radioBand = bandFraction(y, fs, 170, 4700);
highGt6000 = bandFraction(y, fs, 6000, fs / 2);
zcrRatio = zeroCrossingRate(y) / max(zeroCrossingRate(x), eps);
peak = max(abs(y));
row = {mode, diffRmsRatio, centroidHz, lowLt300, teleBand, walkieBand, radioBand, highGt6000, zcrRatio, peak};
end

function y = limitDuration(x, fs, maxSeconds)
x = x(:);
y = x(1:min(numel(x), max(1, round(maxSeconds * fs))));
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

function value = zeroCrossingRate(x)
x = double(x(:));
if numel(x) < 2
    value = 0;
else
    value = mean(abs(diff(sign(x))) > 0);
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
