%RUN_PREPROCESS_VALIDATION Generate listening/check artifacts for preprocessing.
% This script scans samples/*.wav and writes per-sample validation outputs.
% It intentionally does not modify preprocessing or limiter algorithms.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplesDir = fullfile(projectRoot, 'samples');
outputRoot = fullfile(projectRoot, 'results', 'preprocess_validation');
maxDurationSeconds = 20;

if ~exist(outputRoot, 'dir')
    mkdir(outputRoot);
end

sampleFiles = dir(fullfile(samplesDir, '*.wav'));
if isempty(sampleFiles)
    error('run_preprocess_validation:NoSamples', 'No .wav files found in samples/.');
end

rows = cell(numel(sampleFiles), 1);
for k = 1:numel(sampleFiles)
    inputPath = fullfile(sampleFiles(k).folder, sampleFiles(k).name);
    safeName = makeSafeName(eraseExtension(sampleFiles(k).name));
    sampleOutputDir = fullfile(outputRoot, safeName);
    audioDir = fullfile(sampleOutputDir, 'audio');
    figureDir = fullfile(sampleOutputDir, 'figures');
    ensureDir(sampleOutputDir);
    ensureDir(audioDir);
    ensureDir(figureDir);

    try
        row = processOneSample(inputPath, sampleFiles(k).name, sampleOutputDir, audioDir, figureDir, maxDurationSeconds);
    catch ME
        row = makeFailedRow(sampleFiles(k).name, sampleOutputDir, ME.message);
    end
    rows{k} = row;
end

summaryTable = rowsToTable(rows);
summaryPath = fullfile(outputRoot, 'preprocess_summary.csv');
writetable(summaryTable, summaryPath);

fprintf('Preprocess validation finished. Summary: %s\n', summaryPath);

function row = processOneSample(inputPath, inputFileName, outputDir, audioDir, figureDir, maxDurationSeconds)
[xOriginal, fs] = audioread(inputPath);
info = audioinfo(inputPath);
channels = size(xOriginal, 2);
originalDurationSeconds = size(xOriginal, 1) / fs;
numSamples = min(size(xOriginal, 1), max(1, round(maxDurationSeconds * fs)));
xOriginal = xOriginal(1:numSamples, :);
processedDurationSeconds = size(xOriginal, 1) / fs;

rawMono = cleanMonoPreview(xOriginal);

config = makeDefaultConfig();
xDefault = preprocessAudio(xOriginal, fs, config);

configRemoveDC = makeDefaultConfig();
configRemoveDC.audio.removeDC = true;
xRemoveDC = preprocessAudio(xOriginal, fs, configRemoveDC);

configNorm080 = makeDefaultConfig();
configNorm080.audio.normalizeInput = true;
configNorm080.audio.normalizeTargetPeak = 0.8;
xNorm080 = preprocessAudio(xOriginal, fs, configNorm080);

configNorm099 = makeDefaultConfig();
configNorm099.audio.normalizeInput = true;
configNorm099.audio.normalizeTargetPeak = 0.99;
xNorm099 = preprocessAudio(xOriginal, fs, configNorm099);

limitHalfConfig = makeDefaultConfig();
limitHalfConfig.output.limitRange = [-0.5, 0.5];
xLimitHalf = safeLimiter(2 * xNorm099, limitHalfConfig);

limitFullConfig = makeDefaultConfig();
limitFullConfig.output.limitRange = [-1, 1];
xLimitFull = safeLimiter(2 * xNorm099, limitFullConfig);

audioFiles = {
    '00_raw_read_mono_preview.wav', rawMono;
    '01_preprocess_default.wav', xDefault;
    '02_preprocess_remove_dc.wav', xRemoveDC;
    '03_preprocess_normalized_peak_080.wav', xNorm080;
    '04_preprocess_normalized_peak_099.wav', xNorm099;
    '05_safe_limiter_half_range.wav', xLimitHalf;
    '06_safe_limiter_full_range.wav', xLimitFull
};

for n = 1:size(audioFiles, 1)
    writeSafeAudio(fullfile(audioDir, audioFiles{n, 1}), audioFiles{n, 2}, fs);
end

versionNames = {'rawMono', 'default', 'removeDC', 'norm080', 'norm099', 'limitHalf', 'limitFull'};
versionSignals = {rawMono, xDefault, xRemoveDC, xNorm080, xNorm099, xLimitHalf, xLimitFull};
stats = computeStats(versionNames, versionSignals);

saveWaveformOverview(fullfile(figureDir, 'preprocess_waveform_overview.png'), fs, ...
    {'raw mono', 'default', 'removeDC', 'norm peak 0.8', 'limiter half'}, ...
    {rawMono, xDefault, xRemoveDC, xNorm080, xLimitHalf});
saveSpectrumOverview(fullfile(figureDir, 'preprocess_spectrum_overview.png'), fs, ...
    {'raw mono', 'default', 'norm peak 0.8', 'limiter half'}, ...
    {rawMono, xDefault, xNorm080, xLimitHalf});
saveStatsFigure(fullfile(figureDir, 'preprocess_peak_dc_stats.png'), stats);

summaryPath = fullfile(outputDir, 'summary.md');
writeSummary(summaryPath, inputFileName, fs, info.Duration, processedDurationSeconds, channels, audioFiles(:, 1), stats);

row = struct();
row.inputFile = inputFileName;
row.sampleRate = fs;
row.channels = channels;
row.originalDurationSeconds = originalDurationSeconds;
row.processedDurationSeconds = processedDurationSeconds;
row.rawPeak = stats.rawMono.peak;
row.defaultPeak = stats.default.peak;
row.normalizedPeak080 = stats.norm080.peak;
row.normalizedPeak099 = stats.norm099.peak;
row.limitedHalfPeak = stats.limitHalf.peak;
row.rawMean = stats.rawMono.mean;
row.defaultMean = stats.default.mean;
row.removeDCMean = stats.removeDC.mean;
row.rawRMS = stats.rawMono.rms;
row.defaultRMS = stats.default.rms;
row.hasNaNInf = stats.rawMono.hasNaNInf || stats.default.hasNaNInf || stats.removeDC.hasNaNInf || ...
    stats.norm080.hasNaNInf || stats.norm099.hasNaNInf || stats.limitHalf.hasNaNInf || stats.limitFull.hasNaNInf;
row.status = 'passed';
row.message = makeStatusMessage(stats, channels);
row.outputFolder = outputDir;
end

function row = makeFailedRow(inputFileName, outputDir, message)
row = struct();
row.inputFile = inputFileName;
row.sampleRate = NaN;
row.channels = NaN;
row.originalDurationSeconds = NaN;
row.processedDurationSeconds = NaN;
row.rawPeak = NaN;
row.defaultPeak = NaN;
row.normalizedPeak080 = NaN;
row.normalizedPeak099 = NaN;
row.limitedHalfPeak = NaN;
row.rawMean = NaN;
row.defaultMean = NaN;
row.removeDCMean = NaN;
row.rawRMS = NaN;
row.defaultRMS = NaN;
row.hasNaNInf = true;
row.status = 'failed';
row.message = message;
row.outputFolder = outputDir;
end

function tableOut = rowsToTable(rows)
n = numel(rows);
tableOut = table('Size', [n, 19], ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'logical', 'string', 'string', 'string'}, ...
    'VariableNames', {'inputFile', 'sampleRate', 'channels', 'originalDurationSeconds', 'processedDurationSeconds', ...
    'rawPeak', 'defaultPeak', 'normalizedPeak080', 'normalizedPeak099', 'limitedHalfPeak', ...
    'rawMean', 'defaultMean', 'removeDCMean', 'rawRMS', 'defaultRMS', 'hasNaNInf', 'status', 'message', 'outputFolder'});
for k = 1:n
    row = rows{k};
    tableOut.inputFile(k) = string(row.inputFile);
    tableOut.sampleRate(k) = row.sampleRate;
    tableOut.channels(k) = row.channels;
    tableOut.originalDurationSeconds(k) = row.originalDurationSeconds;
    tableOut.processedDurationSeconds(k) = row.processedDurationSeconds;
    tableOut.rawPeak(k) = row.rawPeak;
    tableOut.defaultPeak(k) = row.defaultPeak;
    tableOut.normalizedPeak080(k) = row.normalizedPeak080;
    tableOut.normalizedPeak099(k) = row.normalizedPeak099;
    tableOut.limitedHalfPeak(k) = row.limitedHalfPeak;
    tableOut.rawMean(k) = row.rawMean;
    tableOut.defaultMean(k) = row.defaultMean;
    tableOut.removeDCMean(k) = row.removeDCMean;
    tableOut.rawRMS(k) = row.rawRMS;
    tableOut.defaultRMS(k) = row.defaultRMS;
    tableOut.hasNaNInf(k) = row.hasNaNInf;
    tableOut.status(k) = string(row.status);
    tableOut.message(k) = string(row.message);
    tableOut.outputFolder(k) = string(row.outputFolder);
end
end

function x = cleanMonoPreview(x)
x = double(x);
x(~isfinite(x)) = 0;
if isempty(x)
    x = zeros(0, 1);
elseif size(x, 2) > 1
    x = mean(x, 2);
else
    x = x(:);
end
x(~isfinite(x)) = 0;
end

function writeSafeAudio(pathName, x, fs)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
audiowrite(pathName, x, fs);
end

function stats = computeStats(names, signals)
stats = struct();
for k = 1:numel(names)
    x = double(signals{k});
    x = x(:);
    hasNaNInf = any(~isfinite(x));
    x(~isfinite(x)) = 0;
    item = struct();
    item.mean = meanOrZero(x);
    item.peak = maxOrZero(abs(x));
    item.rms = sqrt(meanOrZero(x.^2));
    item.hasNaNInf = hasNaNInf;
    stats.(names{k}) = item;
end
end

function saveWaveformOverview(pathName, fs, names, signals)
plotSeconds = 4;
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Preprocess Waveform Overview');
for k = 1:numel(names)
    x = signals{k};
    count = min(numel(x), max(1, round(plotSeconds * fs)));
    t = (0:count-1).' / fs;
    subplot(numel(names), 1, k);
    plot(t, x(1:count));
    grid on;
    title(names{k});
    xlabel('Time (s)');
    ylabel('Amp');
end
exportgraphics(fig, pathName, 'Resolution', 150);
close(fig);
end

function saveSpectrumOverview(pathName, fs, names, signals)
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Preprocess Spectrum Overview');
for k = 1:numel(names)
    info = analyzeSpectrum(signals{k}, fs, struct('useDb', true, 'dbFloor', -120));
    subplot(numel(names), 1, k);
    plot(info.f, info.magDb);
    grid on;
    title(names{k});
    xlabel('Frequency (Hz)');
    ylabel('dB');
end
exportgraphics(fig, pathName, 'Resolution', 150);
close(fig);
end

function saveStatsFigure(pathName, stats)
names = {'rawMono', 'default', 'removeDC', 'norm080', 'norm099', 'limitHalf', 'limitFull'};
peaks = zeros(size(names));
rmsValues = zeros(size(names));
means = zeros(size(names));
hasBad = zeros(size(names));
for k = 1:numel(names)
    item = stats.(names{k});
    peaks(k) = item.peak;
    rmsValues(k) = item.rms;
    means(k) = item.mean;
    hasBad(k) = item.hasNaNInf;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Preprocess Peak DC Stats');
subplot(4, 1, 1);
bar(peaks);
set(gca, 'XTickLabel', names);
xtickangle(25);
grid on;
ylabel('Peak');
title('Peak amplitude');

subplot(4, 1, 2);
bar(rmsValues);
set(gca, 'XTickLabel', names);
xtickangle(25);
grid on;
ylabel('RMS');
title('RMS level');

subplot(4, 1, 3);
bar(means);
set(gca, 'XTickLabel', names);
xtickangle(25);
grid on;
ylabel('Mean');
title('Mean / DC offset');

subplot(4, 1, 4);
bar(hasBad);
set(gca, 'XTickLabel', names);
xtickangle(25);
grid on;
ylabel('0/1');
ylim([0, 1]);
title('Has NaN/Inf before cleanup');

exportgraphics(fig, pathName, 'Resolution', 150);
close(fig);
end

function writeSummary(pathName, inputFileName, fs, originalDuration, processedDuration, channels, audioFileNames, stats)
fid = fopen(pathName, 'w', 'n', 'UTF-8');
if fid < 0
    error('run_preprocess_validation:SummaryWriteFailed', 'Cannot write summary.md.');
end
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, '# Preprocess Validation Summary\n\n');
fprintf(fid, '- Input file: `%s`\n', inputFileName);
fprintf(fid, '- Original sample rate: %.0f Hz\n', fs);
fprintf(fid, '- Original duration: %.3f s\n', originalDuration);
fprintf(fid, '- Processed duration: %.3f s\n', processedDuration);
fprintf(fid, '- Original channels: %.0f\n\n', channels);

fprintf(fid, '## Output Audio\n\n');
for k = 1:numel(audioFileNames)
    fprintf(fid, '- `audio/%s`\n', audioFileNames{k});
end

fprintf(fid, '\n## Output Figures\n\n');
fprintf(fid, '- `figures/preprocess_waveform_overview.png`\n');
fprintf(fid, '- `figures/preprocess_spectrum_overview.png`\n');
fprintf(fid, '- `figures/preprocess_peak_dc_stats.png`\n\n');

fprintf(fid, '## Expected Listening Notes\n\n');
fprintf(fid, '- `00_raw_read_mono_preview.wav`: read preview converted to mono for comparison.\n');
fprintf(fid, '- `01_preprocess_default.wav`: should sound almost identical to raw mono preview.\n');
fprintf(fid, '- `02_preprocess_remove_dc.wav`: usually sounds almost unchanged; DC offset should move closer to zero.\n');
fprintf(fid, '- `03_preprocess_normalized_peak_080.wav`: loudness becomes more uniform; pitch and speed should not change.\n');
fprintf(fid, '- `04_preprocess_normalized_peak_099.wav`: may sound louder; obvious distortion would be suspicious.\n');
fprintf(fid, '- `05_safe_limiter_half_range.wav`: intentionally stricter limiter; clipping or flattened loud parts can be audible.\n');
fprintf(fid, '- `06_safe_limiter_full_range.wav`: safety limiter with full [-1, 1] range; should be less aggressive than half range.\n\n');

fprintf(fid, '## Numeric Statistics\n\n');
fprintf(fid, '| Version | Mean/DC | Peak | RMS | Has NaN/Inf |\n');
fprintf(fid, '| --- | ---: | ---: | ---: | --- |\n');
names = {'rawMono', 'default', 'removeDC', 'norm080', 'norm099', 'limitHalf', 'limitFull'};
for k = 1:numel(names)
    item = stats.(names{k});
    fprintf(fid, '| %s | %.8g | %.8g | %.8g | %d |\n', names{k}, item.mean, item.peak, item.rms, item.hasNaNInf);
end

fprintf(fid, '\n## Automatic Notes\n\n');
notes = makeNotes(stats, channels);
for k = 1:numel(notes)
    fprintf(fid, '- %s\n', notes{k});
end
end

function notes = makeNotes(stats, channels)
notes = {};
if channels > 1
    notes{end+1} = 'Input was multi-channel; mono preview/default preprocessing use channel averaging. If the result is much quieter, possible stereo phase cancellation should be checked.';
end
if abs(stats.default.peak - stats.rawMono.peak) > 0.05
    notes{end+1} = 'Default preprocess peak differs noticeably from raw mono preview; inspect whether mono conversion or cleanup changed the sample.';
end
if abs(stats.removeDC.mean) > abs(stats.rawMono.mean) + 1e-8
    notes{end+1} = 'removeDC mean is not closer to zero than raw mean; inspect DC behavior.';
end
if stats.norm080.peak > 0.800001
    notes{end+1} = 'normalized peak 0.8 exceeded expected target.';
end
if stats.norm099.peak > 0.990001
    notes{end+1} = 'normalized peak 0.99 exceeded expected target.';
end
if stats.limitHalf.peak > 0.500001
    notes{end+1} = 'half-range limiter exceeded [-0.5, 0.5].';
end
if stats.rawMono.hasNaNInf || stats.default.hasNaNInf || stats.removeDC.hasNaNInf || stats.norm080.hasNaNInf || stats.limitHalf.hasNaNInf
    notes{end+1} = 'At least one signal contained NaN/Inf before cleanup.';
end
if isempty(notes)
    notes{1} = 'No obvious preprocessing anomaly was detected by numeric checks.';
end
end

function message = makeStatusMessage(stats, channels)
notes = makeNotes(stats, channels);
message = strjoin(notes, ' ');
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function safeName = makeSafeName(name)
safeName = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_|_$', '');
if isempty(safeName)
    safeName = 'sample';
end
end

function name = eraseExtension(fileName)
[~, name, ~] = fileparts(fileName);
end

function value = meanOrZero(x)
if isempty(x)
    value = 0;
else
    value = mean(x);
end
end

function value = maxOrZero(x)
if isempty(x)
    value = 0;
else
    value = max(x);
end
end
