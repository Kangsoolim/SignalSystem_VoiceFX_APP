%EXPORT_AM_REPORT_FIGURES Export report-ready AM modulation/demodulation assets.
%   M08 is kept as a Signals and Systems demonstration: baseband spectrum,
%   carrier-sideband translation, coherent demodulation, and lowpass
%   recovery. The normal realtime/App chain remains disabled by default.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeDefaultConfig();
assert(~config.modDemod.enabled, 'Default modDemod.enabled must stay false.');

fs = 16000;
durationSeconds = 1.5;
t = (0:1/fs:durationSeconds-1/fs).';

baseband = 0.50 * sin(2 * pi * 300 * t) + 0.28 * sin(2 * pi * 900 * t);
baseband = baseband .* tukeyWindowLocal(numel(baseband), 0.08);
baseband = 0.85 * baseband / max(abs(baseband));

modConfig = config.modDemod;
modConfig.enabled = true;
modConfig.type = 'am_modulate';
modConfig.carrierFreq = 4000;
modConfig.modulationIndex = 0.75;
modConfig.messageScale = 0.85;

[modulated, ~, ~] = applyModDemod(baseband, fs, modConfig, initProcessState(config));

demodConfig = config.modDemod;
demodConfig.enabled = true;
demodConfig.type = 'am_demodulate';
demodConfig.carrierFreq = modConfig.carrierFreq;
demodConfig.lowpassCutoff = 1500;
demodConfig.filterOrder = 6;
demodConfig.useZeroPhase = true;
demodConfig.normalizeOutput = true;

[~, demodulated, ~] = applyModDemod(modulated, fs, demodConfig, initProcessState(config));

outRoot = fullfile(projectRoot, 'results', 'stage6_am_report');
figureDir = fullfile(outRoot, 'figures');
audioDir = fullfile(outRoot, 'wav');
ensureDir(figureDir);
ensureDir(audioDir);

baseAudioPath = fullfile(audioDir, 'am_00_baseband.wav');
modAudioPath = fullfile(audioDir, 'am_01_modulated.wav');
demodAudioPath = fullfile(audioDir, 'am_02_demodulated.wav');
audiowrite(baseAudioPath, baseband, fs);
audiowrite(modAudioPath, modulated, fs);
audiowrite(demodAudioPath, demodulated, fs);

baseInfo = analyzeSpectrum(baseband, fs, config.display);
modInfo = analyzeSpectrum(modulated, fs, config.display);
demodInfo = analyzeSpectrum(demodulated, fs, config.display);

spectrumPath = fullfile(figureDir, 'stage6_am_spectrum_shift_recovery.png');
waveformPath = fullfile(figureDir, 'stage6_am_waveform_recovery.png');

fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Stage 6 AM Spectrum Shift and Recovery');
tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plotBand(baseInfo, [0 1800], [0.10 0.35 0.75]);
title('Baseband: 300 Hz and 900 Hz');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

nexttile;
plotBand(modInfo, [0 fs/2], [0.75 0.25 0.10]);
hold on;
drawVerticalMarker(modConfig.carrierFreq, 'Carrier 4 kHz');
title('AM spectrum: carrier plus sidebands');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

nexttile;
plotBand(modInfo, [2800 5200], [0.75 0.25 0.10]);
hold on;
sidebandFreqs = modConfig.carrierFreq + [-900 -300 0 300 900];
for k = 1:numel(sidebandFreqs)
    drawVerticalMarker(sidebandFreqs(k), '');
end
title('Carrier zoom: fc +/- message tones');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

nexttile;
plotBand(demodInfo, [0 1800], [0.20 0.55 0.25]);
hold on;
drawVerticalMarker(demodConfig.lowpassCutoff, 'Lowpass cutoff');
title('Demodulated: low-frequency recovery');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

exportgraphics(fig, spectrumPath, 'Resolution', 180);
close(fig);

plotSamples = min(numel(t), round(0.035 * fs));
plotStartTime = 0.008;
plotStartIndex = min(numel(t), max(1, floor(plotStartTime * fs) + 1));
plotStopIndex = min(numel(t), plotStartIndex + plotSamples - 1);
plotRange = plotStartIndex:plotStopIndex;
plotTime = t(plotRange) - t(plotStartIndex);
demodulatedForPlot = matchRmsForPlot(demodulated, baseband);

fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Stage 6 AM Waveform Recovery');
tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(plotTime, baseband(plotRange), 'Color', [0.10 0.35 0.75]);
grid on;
title('Baseband waveform, first 8 ms omitted');
xlabel('Time (s)');
ylabel('Amplitude');

nexttile;
plot(plotTime, modulated(plotRange), 'Color', [0.75 0.25 0.10]);
grid on;
title('AM waveform, first 8 ms omitted');
xlabel('Time (s)');
ylabel('Amplitude');

nexttile;
plot(plotTime, demodulatedForPlot(plotRange), 'Color', [0.20 0.55 0.25]);
grid on;
title('Recovered waveform, display-normalized to baseband RMS');
xlabel('Time (s)');
ylabel('Display amplitude');

exportgraphics(fig, waveformPath, 'Resolution', 180);
close(fig);

summaryPath = fullfile(outRoot, 'stage6_am_report_summary.txt');
fid = fopen(summaryPath, 'w');
if fid < 0
    error('export_am_report_figures:OpenFailed', 'Cannot write %s.', summaryPath);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Stage 6 AM report assets\n');
fprintf(fid, 'M08 retained: yes, as Signals and Systems spectrum-shift/recovery demo.\n');
fprintf(fid, 'Default modDemod.enabled: false.\n');
fprintf(fid, 'File mode: supported for report figures and audio export.\n');
fprintf(fid, 'Realtime/App first version: not recommended by default.\n');
fprintf(fid, 'normalizeOutput: suitable for full-file exports; not recommended per-frame realtime.\n');
fprintf(fid, 'Spectrum figure: %s\n', spectrumPath);
fprintf(fid, 'Waveform figure: %s\n', waveformPath);
fprintf(fid, 'Audio files:\n');
fprintf(fid, '  %s\n', baseAudioPath);
fprintf(fid, '  %s\n', modAudioPath);
fprintf(fid, '  %s\n', demodAudioPath);
clear cleanupObj;

disp('export_am_report_figures complete.');
disp(['Spectrum figure: ', spectrumPath]);
disp(['Waveform figure: ', waveformPath]);
disp(['Audio dir: ', audioDir]);

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function plotBand(info, xLimits, colorValue)
mask = info.f >= xLimits(1) & info.f <= xLimits(2);
plot(info.f(mask), info.magDb(mask), 'Color', colorValue, 'LineWidth', 1.2);
grid on;
xlim(xLimits);
ylim([-95 5]);
end

function drawVerticalMarker(xValue, labelText)
yLimits = ylim;
line([xValue xValue], yLimits, 'Color', [0.10 0.10 0.10], 'LineStyle', '--', 'LineWidth', 0.8);
if ~isempty(labelText)
    text(xValue, yLimits(2) - 8, labelText, 'Rotation', 90, 'VerticalAlignment', 'top', 'HorizontalAlignment', 'right');
end
end

function yPlot = matchRmsForPlot(y, reference)
yPlot = y;
refRms = sqrt(mean(reference(:).^2));
yRms = sqrt(mean(y(:).^2));
if isfinite(refRms) && isfinite(yRms) && refRms > eps && yRms > eps
    yPlot = y * (refRms / yRms);
end
end

function w = tukeyWindowLocal(n, ratio)
if n <= 1
    w = ones(n, 1);
    return;
end
ratio = min(max(double(ratio), 0), 1);
if ratio <= 0
    w = ones(n, 1);
    return;
end

w = ones(n, 1);
edge = floor(ratio * (n - 1) / 2);
if edge <= 0
    return;
end
idx = (0:edge).';
taper = 0.5 * (1 + cos(pi * (2 * idx / (ratio * (n - 1)) - 1)));
w(1:edge+1) = taper;
w(end-edge:end) = flipud(taper);
end