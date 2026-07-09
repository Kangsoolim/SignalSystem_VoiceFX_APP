function fig = VoiceFXDashboard(varargin)
%VOICEFXDASHBOARD Programmatic VoiceFX control center.
%   FIG = VOICEFXDASHBOARD() launches a modern MATLAB UI that connects the
%   existing processing framework to three workspaces:
%       Live Studio - realtime microphone transformation and telemetry
%       AM Lab      - AM modulation/channel/coherent-demodulation analysis
%       File Studio - realtime-compatible or HQ full-file processing
%
%   The Dashboard contains orchestration and visualization only. DSP remains
%   in core/ and modules/ so file and realtime modes share the same engine.
%
%   VOICEFXDASHBOARD('Visible','off') is useful for UI construction tests.

appDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(appDir);
addpath(genpath(projectRoot));

visible = 'on';
if nargin >= 2 && strcmpi(char(varargin{1}), 'Visible')
    visible = char(varargin{2});
end

% Theme
C.bg = [0.045 0.055 0.082];
C.header = [0.065 0.078 0.115];
C.card = [0.080 0.095 0.140];
C.card2 = [0.105 0.120 0.170];
C.text = [0.94 0.95 0.98];
C.muted = [0.63 0.67 0.76];
C.purple = [0.56 0.42 1.00];
C.cyan = [0.26 0.78 0.95];
C.green = [0.35 0.86 0.62];
C.orange = [1.00 0.67 0.30];
C.red = [1.00 0.42 0.50];
C.grid = [0.23 0.26 0.34];

% Runtime state
liveRunning = false;
liveStopRequested = false;
liveInputBuffer = zeros(0,1);
liveOutputBuffer = zeros(0,1);
liveLastStats = struct();
amSource = zeros(0,1);
amFs = 48000;
amSourceName = 'Generated speech-like demo';
amResult = [];
fileSource = zeros(0,1);
fileProcessed = zeros(0,1);
fileFs = 48000;
fileSourceName = 'No file loaded';
fileDiagnostics = struct();
activePlayer = [];

sampleDir = fullfile(projectRoot, 'samples');
[sampleNames, samplePaths] = discoverSamples(sampleDir);

% Figure shell
fig = uifigure('Name', 'VoiceFX Control Center', ...
    'Position', [70 55 1500 900], 'Color', C.bg, 'Visible', visible, ...
    'CloseRequestFcn', @onCloseFigure);
main = uigridlayout(fig, [2 1]);
main.RowHeight = {72, '1x'};
main.Padding = [16 12 16 16];
main.RowSpacing = 12;
main.BackgroundColor = C.bg;

header = uipanel(main, 'BackgroundColor', C.header, 'BorderType', 'none');
header.Layout.Row = 1;
headerGrid = uigridlayout(header, [1 3]);
headerGrid.ColumnWidth = {'1x', 300, 190};
headerGrid.Padding = [18 8 18 8];
headerGrid.BackgroundColor = C.header;

titleLabel = uilabel(headerGrid, 'Text', 'VOICEFX  /  SIGNAL STUDIO', ...
    'FontSize', 24, 'FontWeight', 'bold', 'FontColor', C.text);
titleLabel.Layout.Column = 1;
subtitle = uilabel(headerGrid, ...
    'Text', 'Adaptive DSP  •  Realtime Chain  •  AM Coherent Lab', ...
    'HorizontalAlignment', 'center', 'FontSize', 12, 'FontColor', C.muted);
subtitle.Layout.Column = 2;
statusBadge = uilabel(headerGrid, 'Text', '●  SYSTEM READY', ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
    'FontColor', C.green, 'BackgroundColor', C.card2);
statusBadge.Layout.Column = 3;

tabs = uitabgroup(main);
tabs.Layout.Row = 2;
liveTab = uitab(tabs, 'Title', '  LIVE STUDIO  ', 'BackgroundColor', C.bg);
amTab = uitab(tabs, 'Title', '  AM LAB  ', 'BackgroundColor', C.bg);
fileTab = uitab(tabs, 'Title', '  FILE STUDIO  ', 'BackgroundColor', C.bg);

%% LIVE STUDIO -----------------------------------------------------------
liveRoot = uigridlayout(liveTab, [1 2]);
liveRoot.ColumnWidth = {360, '1x'};
liveRoot.ColumnSpacing = 12;
liveRoot.Padding = [12 12 12 12];
liveRoot.BackgroundColor = C.bg;

liveControlCard = uipanel(liveRoot, 'Title', 'SESSION CONTROL', ...
    'ForegroundColor', C.text, 'BackgroundColor', C.card, ...
    'FontWeight', 'bold', 'BorderType', 'none');
liveControlCard.Layout.Column = 1;
liveCtl = uigridlayout(liveControlCard, [22 2]);
liveCtl.ColumnWidth = {128, '1x'};
liveCtl.RowHeight = repmat({26}, 1, 22);
liveCtl.Padding = [14 12 14 12];
liveCtl.RowSpacing = 5;
liveCtl.BackgroundColor = C.card;

row = 1;
addTextLabel(liveCtl, row, 'I/O strategy', C);
liveIoMode = uidropdown(liveCtl, 'Items', {'Split devices','Full duplex'}, ...
    'ItemsData', {'split','duplex'}, 'Value', 'split', ...
    'ValueChangedFcn', @onIOModeChanged);
liveIoMode.Layout.Row = row; liveIoMode.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Input device', C);
liveInputDevice = uidropdown(liveCtl, 'Items', {'System default'}, ...
    'ItemsData', {''}, 'Value', '');
liveInputDevice.Layout.Row = row; liveInputDevice.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Output device', C);
liveOutputDevice = uidropdown(liveCtl, 'Items', {'System default'}, ...
    'ItemsData', {''}, 'Value', '');
liveOutputDevice.Layout.Row = row; liveOutputDevice.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Duplex device', C);
liveDuplexDevice = uidropdown(liveCtl, 'Items', {'System default'}, ...
    'ItemsData', {''}, 'Value', '', 'Enable', 'off');
liveDuplexDevice.Layout.Row = row; liveDuplexDevice.Layout.Column = 2; row = row + 1;

refreshDevicesButton = uibutton(liveCtl, 'push', 'Text', '↻  Refresh audio devices', ...
    'ButtonPushedFcn', @onRefreshDevices, 'BackgroundColor', C.card2, ...
    'FontColor', C.text, 'FontWeight', 'bold');
refreshDevicesButton.Layout.Row = row; refreshDevicesButton.Layout.Column = [1 2]; row = row + 1;

addTextLabel(liveCtl, row, 'Sample rate', C);
liveSampleRate = uidropdown(liveCtl, 'Items', {'44.1 kHz','48 kHz'}, ...
    'ItemsData', [44100 48000], 'Value', 48000);
liveSampleRate.Layout.Row = row; liveSampleRate.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Frame size', C);
liveFrameLength = uidropdown(liveCtl, 'Items', {'256','512','1024'}, ...
    'ItemsData', [256 512 1024], 'Value', 512);
liveFrameLength.Layout.Row = row; liveFrameLength.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Voice style', C);
liveVoice = uidropdown(liveCtl, ...
    'Items', {'Female','Male','Child','Elder','Anonymous','Robot Voice'}, ...
    'ItemsData', {'female','male','child','elder','anonymous','robot_voice'}, ...
    'Value', 'female');
liveVoice.Layout.Row = row; liveVoice.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Voice intensity', C);
liveIntensity = uislider(liveCtl, 'Limits', [0 1], 'Value', 0.62, ...
    'MajorTicks', [0 0.5 1]);
liveIntensity.Layout.Row = row; liveIntensity.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Speech clean', C);
liveSpeechClean = uicheckbox(liveCtl, 'Text', 'Adaptive denoise', ...
    'Value', true, 'FontColor', C.text);
liveSpeechClean.Layout.Row = row; liveSpeechClean.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Device FX', C);
liveFxMode = uidropdown(liveCtl, ...
    'Items', {'None','Telephone','Walkie-Talkie','Old Radio','Lo-Fi Tape','Bitcrusher','Gramophone'}, ...
    'ItemsData', {'none','telephone','walkie_talkie','radio','lofi','bitcrusher','gramophone'}, ...
    'Value', 'none');
liveFxMode.Layout.Row = row; liveFxMode.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'FX mix', C);
liveFxMix = uislider(liveCtl, 'Limits', [0 1], 'Value', 0.75, ...
    'MajorTicks', [0 0.5 1]);
liveFxMix.Layout.Row = row; liveFxMix.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Space', C);
liveSpaceMode = uidropdown(liveCtl, 'Items', {'None','Delay','Bathroom','Soft Cave'}, ...
    'ItemsData', {'none','delay','bathroom','cave'}, 'Value', 'none');
liveSpaceMode.Layout.Row = row; liveSpaceMode.Layout.Column = 2; row = row + 1;

addTextLabel(liveCtl, row, 'Space mix', C);
liveSpaceMix = uislider(liveCtl, 'Limits', [0 1], 'Value', 0.30, ...
    'MajorTicks', [0 0.5 1]);
liveSpaceMix.Layout.Row = row; liveSpaceMix.Layout.Column = 2; row = row + 1;

liveStartButton = uibutton(liveCtl, 'push', 'Text', '▶  START LIVE SESSION', ...
    'ButtonPushedFcn', @onStartLive, 'BackgroundColor', C.purple, ...
    'FontColor', [1 1 1], 'FontWeight', 'bold');
liveStartButton.Layout.Row = row; liveStartButton.Layout.Column = [1 2]; row = row + 1;

liveStopButton = uibutton(liveCtl, 'push', 'Text', '■  STOP', ...
    'ButtonPushedFcn', @onStopLive, 'BackgroundColor', C.card2, ...
    'FontColor', C.text, 'FontWeight', 'bold', 'Enable', 'off');
liveStopButton.Layout.Row = row; liveStopButton.Layout.Column = [1 2]; row = row + 1;

liveSessionText = uilabel(liveCtl, 'Text', 'Ready. Configure your chain and start.', ...
    'FontColor', C.muted, 'WordWrap', 'on');
liveSessionText.Layout.Row = [row row+1]; liveSessionText.Layout.Column = [1 2];

liveViz = uigridlayout(liveRoot, [3 1]);
liveViz.RowHeight = {'1x','1x',150};
liveViz.RowSpacing = 12;
liveViz.Padding = [0 0 0 0];
liveViz.BackgroundColor = C.bg;
liveViz.Layout.Column = 2;

liveWaveCard = uipanel(liveViz, 'Title', 'LIVE WAVEFORM  /  INPUT vs OUTPUT', ...
    'ForegroundColor', C.text, 'BackgroundColor', C.card, 'BorderType', 'none');
liveWaveLayout = uigridlayout(liveWaveCard, [1 1]);
liveWaveLayout.Padding = [8 8 8 8];
liveWaveLayout.BackgroundColor = C.card;
liveWaveAxes = uiaxes(liveWaveLayout);
styleAxes(liveWaveAxes, C, 'Time (s)', 'Amplitude');
liveInputLine = plot(liveWaveAxes, nan, nan, 'LineWidth', 1.0, 'Color', C.cyan);
hold(liveWaveAxes, 'on');
liveOutputLine = plot(liveWaveAxes, nan, nan, 'LineWidth', 1.2, 'Color', C.purple);
legend(liveWaveAxes, {'Input','Output'}, 'TextColor', C.text, ...
    'Color', C.card, 'EdgeColor', C.card2, 'Location', 'northeast');

liveSpecCard = uipanel(liveViz, 'Title', 'SPECTRAL MONITOR', ...
    'ForegroundColor', C.text, 'BackgroundColor', C.card, 'BorderType', 'none');
liveSpecLayout = uigridlayout(liveSpecCard, [1 1]);
liveSpecLayout.Padding = [8 8 8 8];
liveSpecLayout.BackgroundColor = C.card;
liveSpecAxes = uiaxes(liveSpecLayout);
styleAxes(liveSpecAxes, C, 'Frequency (Hz)', 'Magnitude (dB)');
liveInputSpecLine = plot(liveSpecAxes, nan, nan, 'LineWidth', 1.0, 'Color', C.cyan);
hold(liveSpecAxes, 'on');
liveOutputSpecLine = plot(liveSpecAxes, nan, nan, 'LineWidth', 1.2, 'Color', C.purple);
ylim(liveSpecAxes, [-80 5]);

metricGrid = uigridlayout(liveViz, [1 6]);
metricGrid.ColumnWidth = repmat({'1x'}, 1, 6);
metricGrid.ColumnSpacing = 8;
metricGrid.Padding = [0 0 0 0];
metricGrid.BackgroundColor = C.bg;
[liveMetricProcess, ~] = metricTile(metricGrid, 'MEAN PROCESS', '-- ms', C);
[liveMetricP95, ~] = metricTile(metricGrid, 'P95 PROCESS', '-- ms', C);
[liveMetricRTF, ~] = metricTile(metricGrid, 'RTF', '--', C);
[liveMetricBudget, ~] = metricTile(metricGrid, 'BUFFER BUDGET*', '-- ms', C);
[liveMetricXRuns, ~] = metricTile(metricGrid, 'XRUN SAMPLES', '0', C);
[liveMetricLevel, ~] = metricTile(metricGrid, 'OUTPUT RMS', '-- dB', C);

%% AM LAB ----------------------------------------------------------------
amRoot = uigridlayout(amTab, [1 2]);
amRoot.ColumnWidth = {380, '1x'};
amRoot.ColumnSpacing = 12;
amRoot.Padding = [12 12 12 12];
amRoot.BackgroundColor = C.bg;

amControlCard = uipanel(amRoot, 'Title', 'TRANSMITTER  →  CHANNEL  →  RECEIVER', ...
    'ForegroundColor', C.text, 'BackgroundColor', C.card, ...
    'FontWeight', 'bold', 'BorderType', 'none');
amCtl = uigridlayout(amControlCard, [21 2]);
amCtl.ColumnWidth = {145, '1x'};
amCtl.RowHeight = repmat({26}, 1, 21);
amCtl.Padding = [14 12 14 12];
amCtl.RowSpacing = 5;
amCtl.BackgroundColor = C.card;

row = 1;
addTextLabel(amCtl, row, 'Project sample', C);
amSample = uidropdown(amCtl, 'Items', sampleNames, 'ItemsData', samplePaths);
amSample.Layout.Row = row; amSample.Layout.Column = 2; row = row + 1;

amLoadSampleButton = uibutton(amCtl, 'push', 'Text', 'Load selected sample', ...
    'ButtonPushedFcn', @onLoadAMSample, 'BackgroundColor', C.card2, 'FontColor', C.text);
amLoadSampleButton.Layout.Row = row; amLoadSampleButton.Layout.Column = [1 2]; row = row + 1;

amBrowseButton = uibutton(amCtl, 'push', 'Text', 'Browse audio file…', ...
    'ButtonPushedFcn', @onBrowseAM, 'BackgroundColor', C.card2, 'FontColor', C.text);
amBrowseButton.Layout.Row = row; amBrowseButton.Layout.Column = [1 2]; row = row + 1;

addTextLabel(amCtl, row, 'Carrier frequency', C);
amCarrier = uispinner(amCtl, 'Limits', [100 20000], 'Step', 100, 'Value', 8000);
amCarrier.Layout.Row = row; amCarrier.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'Modulation index μ', C);
amMu = uispinner(amCtl, 'Limits', [0 1.5], 'Step', 0.05, 'Value', 0.70);
amMu.Layout.Row = row; amMu.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'Message scale', C);
amMessageScale = uispinner(amCtl, 'Limits', [0.05 1], 'Step', 0.05, 'Value', 0.80);
amMessageScale.Layout.Row = row; amMessageScale.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'Channel SNR (dB)', C);
amSnr = uispinner(amCtl, 'Limits', [-10 80], 'Step', 1, 'Value', 35);
amSnr.Layout.Row = row; amSnr.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'Rx phase error (°)', C);
amPhaseError = uispinner(amCtl, 'Limits', [-180 180], 'Step', 5, 'Value', 0);
amPhaseError.Layout.Row = row; amPhaseError.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'Rx freq error (Hz)', C);
amFreqError = uispinner(amCtl, 'Limits', [-500 500], 'Step', 5, 'Value', 0);
amFreqError.Layout.Row = row; amFreqError.Layout.Column = 2; row = row + 1;

addTextLabel(amCtl, row, 'LPF cutoff (Hz)', C);
amCutoff = uispinner(amCtl, 'Limits', [100 12000], 'Step', 100, 'Value', 3400);
amCutoff.Layout.Row = row; amCutoff.Layout.Column = 2; row = row + 1;

amRunButton = uibutton(amCtl, 'push', 'Text', '◆  RUN AM EXPERIMENT', ...
    'ButtonPushedFcn', @onRunAM, 'BackgroundColor', C.purple, ...
    'FontColor', [1 1 1], 'FontWeight', 'bold');
amRunButton.Layout.Row = row; amRunButton.Layout.Column = [1 2]; row = row + 1;

amPlayOriginal = uibutton(amCtl, 'push', 'Text', 'Play original', ...
    'ButtonPushedFcn', @onPlayAMOriginal, 'BackgroundColor', C.card2, 'FontColor', C.text);
amPlayOriginal.Layout.Row = row; amPlayOriginal.Layout.Column = [1 2]; row = row + 1;
amPlayChannel = uibutton(amCtl, 'push', 'Text', 'Play AM channel', ...
    'ButtonPushedFcn', @onPlayAMChannel, 'BackgroundColor', C.card2, 'FontColor', C.text);
amPlayChannel.Layout.Row = row; amPlayChannel.Layout.Column = [1 2]; row = row + 1;
amPlayRecovered = uibutton(amCtl, 'push', 'Text', 'Play recovered', ...
    'ButtonPushedFcn', @onPlayAMRecovered, 'BackgroundColor', C.card2, 'FontColor', C.text);
amPlayRecovered.Layout.Row = row; amPlayRecovered.Layout.Column = [1 2]; row = row + 1;

amSourceLabel = uilabel(amCtl, 'Text', 'Source: generated demo', ...
    'FontColor', C.muted, 'WordWrap', 'on');
amSourceLabel.Layout.Row = [row row+1]; amSourceLabel.Layout.Column = [1 2]; row = row + 2;

amHint = uilabel(amCtl, ...
    'Text', ['Explore phase/frequency mismatch and channel noise. ', ...
             'μ × message scale > 1 indicates envelope overmodulation risk.'], ...
    'FontColor', C.muted, 'WordWrap', 'on');
amHint.Layout.Row = [row min(row+2,21)]; amHint.Layout.Column = [1 2];

amViz = uigridlayout(amRoot, [3 2]);
amViz.RowHeight = {'1x','1x',120};
amViz.ColumnWidth = {'1x','1x'};
amViz.RowSpacing = 10;
amViz.ColumnSpacing = 10;
amViz.Padding = [0 0 0 0];
amViz.BackgroundColor = C.bg;

amBaseAxes = cardAxes(amViz, [1 1], 'BASEBAND MESSAGE', C, 'Time (s)', 'Amplitude');
amEnvelopeAxes = cardAxes(amViz, [1 2], 'AM CARRIER + ENVELOPE', C, 'Time (s)', 'Amplitude');
amSpectrumAxes = cardAxes(amViz, [2 1], 'SPECTRUM SHIFTING', C, 'Frequency (Hz)', 'Magnitude (dB)');
amRecoverAxes = cardAxes(amViz, [2 2], 'COHERENT RECOVERY', C, 'Time (s)', 'Amplitude');

amMetrics = uigridlayout(amViz, [1 5]);
amMetrics.Layout.Row = 3; amMetrics.Layout.Column = [1 2];
amMetrics.ColumnWidth = repmat({'1x'}, 1, 5);
amMetrics.ColumnSpacing = 8;
amMetrics.Padding = [0 0 0 0];
amMetrics.BackgroundColor = C.bg;
[amMetricCorr, ~] = metricTile(amMetrics, 'CORRELATION', '--', C);
[amMetricSnr, ~] = metricTile(amMetrics, 'RECON SNR', '-- dB', C);
[amMetricNmse, ~] = metricTile(amMetrics, 'NMSE', '--', C);
[amMetricBw, ~] = metricTile(amMetrics, 'EST. AM BW', '-- Hz', C);
[amMetricEnvelope, amMetricEnvelopeTitle] = metricTile(amMetrics, 'ENVELOPE MARGIN', '--', C);

%% FILE STUDIO -----------------------------------------------------------
fileRoot = uigridlayout(fileTab, [1 2]);
fileRoot.ColumnWidth = {370, '1x'};
fileRoot.ColumnSpacing = 12;
fileRoot.Padding = [12 12 12 12];
fileRoot.BackgroundColor = C.bg;

fileControlCard = uipanel(fileRoot, 'Title', 'OFFLINE PROCESSING CHAIN', ...
    'ForegroundColor', C.text, 'BackgroundColor', C.card, ...
    'FontWeight', 'bold', 'BorderType', 'none');
fileCtl = uigridlayout(fileControlCard, [21 2]);
fileCtl.ColumnWidth = {135, '1x'};
fileCtl.RowHeight = repmat({26}, 1, 21);
fileCtl.Padding = [14 12 14 12];
fileCtl.RowSpacing = 5;
fileCtl.BackgroundColor = C.card;

row = 1;
addTextLabel(fileCtl, row, 'Project sample', C);
fileSample = uidropdown(fileCtl, 'Items', sampleNames, 'ItemsData', samplePaths);
fileSample.Layout.Row = row; fileSample.Layout.Column = 2; row = row + 1;

fileLoadSampleButton = uibutton(fileCtl, 'push', 'Text', 'Load selected sample', ...
    'ButtonPushedFcn', @onLoadFileSample, 'BackgroundColor', C.card2, 'FontColor', C.text);
fileLoadSampleButton.Layout.Row = row; fileLoadSampleButton.Layout.Column = [1 2]; row = row + 1;

fileBrowseButton = uibutton(fileCtl, 'push', 'Text', 'Browse audio file…', ...
    'ButtonPushedFcn', @onBrowseFile, 'BackgroundColor', C.card2, 'FontColor', C.text);
fileBrowseButton.Layout.Row = row; fileBrowseButton.Layout.Column = [1 2]; row = row + 1;

addTextLabel(fileCtl, row, 'Engine', C);
fileEngine = uidropdown(fileCtl, 'Items', {'Realtime-compatible DSP','HQ full-utterance'}, ...
    'ItemsData', {'realtime','hq'}, 'Value', 'hq');
fileEngine.Layout.Row = row; fileEngine.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Voice style', C);
fileVoice = uidropdown(fileCtl, ...
    'Items', {'Female','Male','Child','Elder','Anonymous','Robot Voice'}, ...
    'ItemsData', {'female','male','child','elder','anonymous','robot_voice'}, ...
    'Value', 'female');
fileVoice.Layout.Row = row; fileVoice.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Voice intensity', C);
fileIntensity = uislider(fileCtl, 'Limits', [0 1], 'Value', 0.62, ...
    'MajorTicks', [0 0.5 1]);
fileIntensity.Layout.Row = row; fileIntensity.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Speech clean', C);
fileSpeechClean = uicheckbox(fileCtl, 'Text', 'Adaptive denoise', ...
    'Value', true, 'FontColor', C.text);
fileSpeechClean.Layout.Row = row; fileSpeechClean.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Device FX', C);
fileFxMode = uidropdown(fileCtl, ...
    'Items', {'None','Telephone','Walkie-Talkie','Old Radio','Lo-Fi Tape','Bitcrusher','Gramophone'}, ...
    'ItemsData', {'none','telephone','walkie_talkie','radio','lofi','bitcrusher','gramophone'}, ...
    'Value', 'none');
fileFxMode.Layout.Row = row; fileFxMode.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'FX mix', C);
fileFxMix = uislider(fileCtl, 'Limits', [0 1], 'Value', 0.75, ...
    'MajorTicks', [0 0.5 1]);
fileFxMix.Layout.Row = row; fileFxMix.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Space', C);
fileSpaceMode = uidropdown(fileCtl, 'Items', {'None','Delay','Bathroom','Soft Cave'}, ...
    'ItemsData', {'none','delay','bathroom','cave'}, 'Value', 'none');
fileSpaceMode.Layout.Row = row; fileSpaceMode.Layout.Column = 2; row = row + 1;

addTextLabel(fileCtl, row, 'Space mix', C);
fileSpaceMix = uislider(fileCtl, 'Limits', [0 1], 'Value', 0.30, ...
    'MajorTicks', [0 0.5 1]);
fileSpaceMix.Layout.Row = row; fileSpaceMix.Layout.Column = 2; row = row + 1;

fileProcessButton = uibutton(fileCtl, 'push', 'Text', '◆  PROCESS FILE', ...
    'ButtonPushedFcn', @onProcessFile, 'BackgroundColor', C.purple, ...
    'FontColor', [1 1 1], 'FontWeight', 'bold');
fileProcessButton.Layout.Row = row; fileProcessButton.Layout.Column = [1 2]; row = row + 1;

filePlayOriginal = uibutton(fileCtl, 'push', 'Text', 'Play original', ...
    'ButtonPushedFcn', @onPlayFileOriginal, 'BackgroundColor', C.card2, 'FontColor', C.text);
filePlayOriginal.Layout.Row = row; filePlayOriginal.Layout.Column = [1 2]; row = row + 1;
filePlayProcessed = uibutton(fileCtl, 'push', 'Text', 'Play processed', ...
    'ButtonPushedFcn', @onPlayFileProcessed, 'BackgroundColor', C.card2, 'FontColor', C.text);
filePlayProcessed.Layout.Row = row; filePlayProcessed.Layout.Column = [1 2]; row = row + 1;
fileSaveButton = uibutton(fileCtl, 'push', 'Text', 'Export processed WAV…', ...
    'ButtonPushedFcn', @onSaveFile, 'BackgroundColor', C.card2, 'FontColor', C.text);
fileSaveButton.Layout.Row = row; fileSaveButton.Layout.Column = [1 2]; row = row + 1;

fileSourceLabel = uilabel(fileCtl, 'Text', fileSourceName, ...
    'FontColor', C.muted, 'WordWrap', 'on');
fileSourceLabel.Layout.Row = [row row+1]; fileSourceLabel.Layout.Column = [1 2]; row = row + 2;
fileStatusLabel = uilabel(fileCtl, 'Text', 'Load a source, choose chain, process.', ...
    'FontColor', C.muted, 'WordWrap', 'on');
fileStatusLabel.Layout.Row = [row min(row+2,21)]; fileStatusLabel.Layout.Column = [1 2];

fileViz = uigridlayout(fileRoot, [3 1]);
fileViz.RowHeight = {'1x','1x',130};
fileViz.RowSpacing = 12;
fileViz.Padding = [0 0 0 0];
fileViz.BackgroundColor = C.bg;
fileWaveAxes = cardAxes(fileViz, [1 1], 'BEFORE / AFTER WAVEFORM', C, 'Time (s)', 'Amplitude');
fileSpectrumAxes = cardAxes(fileViz, [2 1], 'BEFORE / AFTER SPECTRUM', C, 'Frequency (Hz)', 'Magnitude (dB)');
fileMetrics = uigridlayout(fileViz, [1 4]);
fileMetrics.Layout.Row = 3;
fileMetrics.ColumnWidth = repmat({'1x'},1,4);
fileMetrics.ColumnSpacing = 8;
fileMetrics.Padding = [0 0 0 0];
fileMetrics.BackgroundColor = C.bg;
[fileMetricDuration, ~] = metricTile(fileMetrics, 'AUDIO DURATION', '-- s', C);
[fileMetricProcess, ~] = metricTile(fileMetrics, 'PROCESS TIME', '-- s', C);
[fileMetricRTF, ~] = metricTile(fileMetrics, 'OFFLINE RTF', '--', C);
[fileMetricPeak, ~] = metricTile(fileMetrics, 'OUTPUT PEAK', '-- dB', C);

% Initialize safe demo/sample state after every handle exists.
loadGeneratedAMDemo();
initializeSampleDropdowns();
onRefreshDevices([], []);
onIOModeChanged([], []);

%% Nested callbacks -------------------------------------------------------
    function onRefreshDevices(~, ~)
        try
            devices = listAudioDevices(false);
            setDeviceDropdown(liveInputDevice, devices.input);
            setDeviceDropdown(liveOutputDevice, devices.output);
            setDeviceDropdown(liveDuplexDevice, devices.duplex);
            liveSessionText.Text = sprintf('Found %d input, %d output, %d duplex device(s).', ...
                numel(devices.input), numel(devices.output), numel(devices.duplex));
        catch ME
            setDeviceDropdown(liveInputDevice, {});
            setDeviceDropdown(liveOutputDevice, {});
            setDeviceDropdown(liveDuplexDevice, {});
            liveSessionText.Text = ['Audio device discovery unavailable: ' ME.message];
        end
    end

    function onIOModeChanged(~, ~)
        isDuplex = strcmp(liveIoMode.Value, 'duplex');
        liveInputDevice.Enable = onOff(~isDuplex && ~liveRunning);
        liveOutputDevice.Enable = onOff(~isDuplex && ~liveRunning);
        liveDuplexDevice.Enable = onOff(isDuplex && ~liveRunning);
    end

    function options = collectLiveOptions()
        options = struct();
        options.sampleRate = liveSampleRate.Value;
        options.frameLength = liveFrameLength.Value;
        options.ioMode = liveIoMode.Value;
        options.inputDevice = liveInputDevice.Value;
        options.outputDevice = liveOutputDevice.Value;
        options.duplexDevice = liveDuplexDevice.Value;
        options.intensity = liveIntensity.Value;
        options.enableSpeechClean = liveSpeechClean.Value;
        options.fxMode = liveFxMode.Value;
        options.fxMix = liveFxMix.Value;
        options.fxIntensity = 0.65;
        options.spaceMode = liveSpaceMode.Value;
        options.spaceMix = liveSpaceMix.Value;
        options.monitorInterval = 0.10;
        options.controlInterval = 0.08;
        options.rollingWindowSeconds = 3.0;
        options.monitorFcn = @onLiveMonitor;
        options.controlFcn = @collectLiveConfig;
        options.stopFcn = @shouldStopLive;
        options.processUIEvents = true;
    end

    function config = collectLiveConfig()
        update = struct();
        update.frameLength = liveFrameLength.Value;
        update.intensity = liveIntensity.Value;
        update.enableSpeechClean = liveSpeechClean.Value;
        update.fxMode = liveFxMode.Value;
        update.fxMix = liveFxMix.Value;
        update.fxIntensity = 0.65;
        update.spaceMode = liveSpaceMode.Value;
        update.spaceMix = liveSpaceMix.Value;
        config = buildRealtimeConfig(liveVoice.Value, update);
    end

    function tf = shouldStopLive()
        tf = liveStopRequested || ~isvalid(fig);
    end

    function onStartLive(~, ~)
        if liveRunning
            return;
        end
        liveStopRequested = false;
        liveRunning = true;
        liveInputBuffer = zeros(0,1);
        liveOutputBuffer = zeros(0,1);
        setLiveRunningState(true);
        liveSessionText.Text = 'Starting audio devices and calibration…';
        statusBadge.Text = '●  LIVE SESSION';
        statusBadge.FontColor = C.orange;
        drawnow;
        options = collectLiveOptions();
        try
            liveLastStats = runRealtimeVoiceChanger(Inf, liveVoice.Value, options);
            if isvalid(fig)
                liveSessionText.Text = sprintf('Session complete: %d frames, mean %.2f ms, P95 %.2f ms.', ...
                    liveLastStats.framesProcessed, liveLastStats.meanProcessMs, liveLastStats.p95ProcessMs);
            end
        catch ME
            if isvalid(fig)
                liveSessionText.Text = ['Live session error: ' ME.message];
                uialert(fig, ME.message, 'Realtime session error');
            end
        end
        liveRunning = false;
        liveStopRequested = false;
        if isvalid(fig)
            setLiveRunningState(false);
            statusBadge.Text = '●  SYSTEM READY';
            statusBadge.FontColor = C.green;
        end
    end

    function onStopLive(~, ~)
        liveStopRequested = true;
        liveSessionText.Text = 'Stopping after the current audio frame…';
        liveStopButton.Enable = 'off';
    end

    function setLiveRunningState(running)
        liveStartButton.Enable = onOff(~running);
        liveStopButton.Enable = onOff(running);
        liveSampleRate.Enable = onOff(~running);
        liveFrameLength.Enable = onOff(~running);
        liveIoMode.Enable = onOff(~running);
        refreshDevicesButton.Enable = onOff(~running);
        onIOModeChanged([], []);
    end

    function onLiveMonitor(snapshot)
        keepSamples = min(round(0.30 * snapshot.sampleRate), 16000);
        liveInputBuffer = appendTail(liveInputBuffer, snapshot.inputFrame, keepSamples);
        liveOutputBuffer = appendTail(liveOutputBuffer, snapshot.outputFrame, keepSamples);
        t = (0:numel(liveInputBuffer)-1).' / snapshot.sampleRate;
        liveInputLine.XData = t;
        liveInputLine.YData = liveInputBuffer;
        liveOutputLine.XData = t;
        liveOutputLine.YData = liveOutputBuffer;
        if ~isempty(t)
            xlim(liveWaveAxes, [max(0, t(end)-0.30), max(0.01, t(end))]);
        end
        [fIn, dbIn] = dashboardSpectrum(snapshot.inputFrame, snapshot.sampleRate, 4096);
        [fOut, dbOut] = dashboardSpectrum(snapshot.outputFrame, snapshot.sampleRate, 4096);
        liveInputSpecLine.XData = fIn; liveInputSpecLine.YData = dbIn;
        liveOutputSpecLine.XData = fOut; liveOutputSpecLine.YData = dbOut;
        xlim(liveSpecAxes, [0 min(12000, snapshot.sampleRate/2)]);

        liveMetricProcess.Text = sprintf('%.2f ms', snapshot.meanProcessMs);
        liveMetricP95.Text = sprintf('%.2f ms', snapshot.p95ProcessMs);
        liveMetricRTF.Text = sprintf('%.3f', snapshot.realtimeFactor);
        liveMetricBudget.Text = sprintf('%.1f ms', snapshot.nominalBufferBudgetMs);
        liveMetricXRuns.Text = sprintf('%d', snapshot.totalOverrunSamples + snapshot.totalUnderrunSamples);
        liveMetricLevel.Text = sprintf('%.1f dB', snapshot.outputRmsDb);
        liveSessionText.Text = sprintf('LIVE · %s · %s · %s · frame %d', ...
            snapshot.voiceMode, snapshot.fxMode, snapshot.spaceMode, snapshot.frameCount);
    end

    function onLoadAMSample(~, ~)
        path = amSample.Value;
        if isempty(path)
            loadGeneratedAMDemo();
            return;
        end
        loadAMPath(path);
    end

    function onBrowseAM(~, ~)
        [name, folder] = uigetfile({'*.wav;*.flac;*.mp3;*.m4a','Audio files'}, ...
            'Choose AM Lab source');
        if isequal(name, 0)
            return;
        end
        loadAMPath(fullfile(folder, name));
    end

    function loadAMPath(path)
        try
            [x, sourceFs] = audioread(path);
            amSource = cleanDashboardAudio(x);
            amFs = sourceFs;
            [~, stem, ext] = fileparts(path);
            amSourceName = [stem ext];
            amSourceLabel.Text = sprintf('Source: %s · %.1f s · %g Hz', ...
                amSourceName, numel(amSource)/amFs, amFs);
            carrierMax = max(200, floor(amFs/2 - 200));
            carrierValue = min(max(amCarrier.Value, 100), carrierMax);
            amCarrier.Value = carrierValue;
            amCarrier.Limits = [100 carrierMax];
            cutoffMax = max(100, floor(0.42*amFs));
            cutoffValue = min(max(amCutoff.Value, 50), cutoffMax);
            amCutoff.Value = cutoffValue;
            amCutoff.Limits = [50 cutoffMax];
            plotAMSourcePreview();
        catch ME
            uialert(fig, ME.message, 'AM source load error');
        end
    end

    function loadGeneratedAMDemo()
        amFs = 48000;
        duration = 3.5;
        t = (0:round(duration*amFs)-1).' / amFs;
        f0 = 145 + 30*sin(2*pi*0.65*t) + 12*sin(2*pi*0.17*t);
        phase = cumsum(2*pi*f0/amFs);
        excitation = sin(phase) + 0.35*sin(2*phase+0.4) + 0.16*sin(3*phase+0.7);
        syllableEnv = 0.35 + 0.65*(0.5 + 0.5*sin(2*pi*2.2*t)).^2;
        phraseEnv = min(1, t/0.18) .* min(1, (duration-t)/0.25);
        phraseEnv = max(phraseEnv, 0);
        amSource = 0.55 * excitation .* syllableEnv .* phraseEnv;
        amSourceName = 'Generated speech-like demo';
        if exist('amSourceLabel','var') && isvalid(amSourceLabel)
            amSourceLabel.Text = sprintf('Source: %s · %.1f s · %g Hz', ...
                amSourceName, duration, amFs);
            plotAMSourcePreview();
        end
    end

    function plotAMSourcePreview()
        cla(amBaseAxes);
        n = min(numel(amSource), round(0.08*amFs));
        t = (0:n-1).' / amFs;
        plot(amBaseAxes, t, amSource(1:n), 'Color', C.cyan, 'LineWidth', 1.2);
        title(amBaseAxes, ['Baseband preview · ' amSourceName], 'Color', C.text);
    end

    function onRunAM(~, ~)
        if isempty(amSource)
            loadGeneratedAMDemo();
        end
        options = struct();
        options.carrierFreq = amCarrier.Value;
        options.modulationIndex = amMu.Value;
        options.messageScale = amMessageScale.Value;
        options.channelSnrDb = amSnr.Value;
        options.receiverPhaseOffsetDeg = amPhaseError.Value;
        options.receiverFreqOffsetHz = amFreqError.Value;
        options.lowpassCutoff = amCutoff.Value;
        options.filterOrder = 4;
        options.experimentSeed = 7;
        amRunButton.Enable = 'off';
        amRunButton.Text = 'RUNNING…';
        drawnow;
        try
            amResult = runAMExperiment(amSource, amFs, options);
            updateAMPlots();
            updateAMMetrics();
            statusBadge.Text = '●  AM EXPERIMENT COMPLETE';
            statusBadge.FontColor = C.cyan;
        catch ME
            uialert(fig, ME.message, 'AM experiment error');
        end
        amRunButton.Enable = 'on';
        amRunButton.Text = '◆  RUN AM EXPERIMENT';
    end

    function updateAMPlots()
        r = amResult;
        nBase = min(numel(r.original), round(0.08*r.fs));
        tBase = (0:nBase-1).' / r.fs;
        cla(amBaseAxes);
        plot(amBaseAxes, tBase, r.original(1:nBase), 'Color', C.cyan, 'LineWidth', 1.2);
        title(amBaseAxes, 'Baseband message', 'Color', C.text);

        nCarrier = min(numel(r.modulated), round(0.008*r.fs));
        tCarrier = (0:nCarrier-1).' / r.fs;
        cla(amEnvelopeAxes);
        plot(amEnvelopeAxes, tCarrier, r.modulated(1:nCarrier), 'Color', C.purple, 'LineWidth', 0.9);
        hold(amEnvelopeAxes, 'on');
        env = r.envelope(1:nCarrier);
        plot(amEnvelopeAxes, tCarrier, env, 'Color', C.orange, 'LineWidth', 1.3);
        plot(amEnvelopeAxes, tCarrier, -env, 'Color', C.orange, 'LineWidth', 1.0);
        title(amEnvelopeAxes, sprintf('AM carrier %.0f Hz · μ %.2f', ...
            r.txConfig.carrierFreq, r.metrics.modulationIndex), 'Color', C.text);

        cla(amSpectrumAxes);
        plot(amSpectrumAxes, r.spectra.original.frequency, ...
            r.spectra.original.magnitudeDb, 'Color', C.cyan, 'LineWidth', 1.0);
        hold(amSpectrumAxes, 'on');
        plot(amSpectrumAxes, r.spectra.modulated.frequency, ...
            r.spectra.modulated.magnitudeDb, 'Color', C.purple, 'LineWidth', 1.1);
        xlim(amSpectrumAxes, [0 min(r.fs/2, r.txConfig.carrierFreq + 1.6*amCutoff.Value)]);
        ylim(amSpectrumAxes, [-80 5]);
        legend(amSpectrumAxes, {'Baseband','AM'}, 'TextColor', C.text, ...
            'Color', C.card, 'EdgeColor', C.card2, 'Location', 'southwest');

        startIndex = min(numel(r.original), max(1, round(0.08*r.fs)));
        nRecover = min(round(0.10*r.fs), numel(r.original)-startIndex+1);
        idx = startIndex:(startIndex+nRecover-1);
        tRecover = (0:nRecover-1).' / r.fs;
        cla(amRecoverAxes);
        plot(amRecoverAxes, tRecover, r.original(idx), 'Color', C.cyan, 'LineWidth', 1.1);
        hold(amRecoverAxes, 'on');
        plot(amRecoverAxes, tRecover, r.demodulated(idx), 'Color', C.purple, 'LineWidth', 1.1);
        title(amRecoverAxes, sprintf('Rx Δf %.1f Hz · Δφ %.0f°', ...
            r.metrics.receiverFrequencyOffsetHz, r.metrics.receiverPhaseOffsetDeg), 'Color', C.text);
        legend(amRecoverAxes, {'Original','Recovered'}, 'TextColor', C.text, ...
            'Color', C.card, 'EdgeColor', C.card2, 'Location', 'northeast');
    end

    function updateAMMetrics()
        m = amResult.metrics;
        amMetricCorr.Text = sprintf('%.4f', m.correlation);
        amMetricSnr.Text = sprintf('%.2f dB', m.reconstructionSnrDb);
        amMetricNmse.Text = sprintf('%.4f', m.nmse);
        amMetricBw.Text = sprintf('%.0f Hz', m.estimatedAMBandwidthHz);
        amMetricEnvelope.Text = sprintf('%.3f', m.envelopeMinimum);
        if m.overmodulated
            amMetricEnvelope.FontColor = C.red;
            amMetricEnvelopeTitle.Text = 'OVERMODULATION RISK';
        else
            amMetricEnvelope.FontColor = C.green;
            amMetricEnvelopeTitle.Text = 'ENVELOPE MARGIN';
        end
    end

    function onPlayAMOriginal(~, ~)
        playDashboardAudio(amSource, amFs);
    end

    function onPlayAMChannel(~, ~)
        requireAMResult();
        if ~isempty(amResult)
            playDashboardAudio(amResult.channel, amResult.fs);
        end
    end

    function onPlayAMRecovered(~, ~)
        requireAMResult();
        if ~isempty(amResult)
            playDashboardAudio(amResult.demodulated, amResult.fs);
        end
    end

    function requireAMResult()
        if isempty(amResult)
            onRunAM([], []);
        end
    end

    function onLoadFileSample(~, ~)
        path = fileSample.Value;
        if ~isempty(path)
            loadFilePath(path);
        end
    end

    function onBrowseFile(~, ~)
        [name, folder] = uigetfile({'*.wav;*.flac;*.mp3;*.m4a','Audio files'}, ...
            'Choose source file');
        if isequal(name, 0)
            return;
        end
        loadFilePath(fullfile(folder, name));
    end

    function loadFilePath(path)
        try
            [x, sourceFs] = audioread(path);
            fileSource = cleanDashboardAudio(x);
            fileProcessed = zeros(0,1);
            fileFs = sourceFs;
            [~, stem, ext] = fileparts(path);
            fileSourceName = [stem ext];
            fileSourceLabel.Text = sprintf('%s · %.1f s · %g Hz', ...
                fileSourceName, numel(fileSource)/fileFs, fileFs);
            fileStatusLabel.Text = 'Source loaded. Ready to process.';
            fileMetricDuration.Text = sprintf('%.2f s', numel(fileSource)/fileFs);
            updateFilePlots(false);
        catch ME
            uialert(fig, ME.message, 'File load error');
        end
    end

    function onProcessFile(~, ~)
        if isempty(fileSource)
            if ~isempty(fileSample.Value)
                loadFilePath(fileSample.Value);
            else
                uialert(fig, 'Load a source file first.', 'No source');
                return;
            end
        end
        opts = struct();
        opts.frameLength = 1024;
        opts.intensity = fileIntensity.Value;
        opts.enableSpeechClean = fileSpeechClean.Value;
        opts.fxMode = fileFxMode.Value;
        opts.fxMix = fileFxMix.Value;
        opts.fxIntensity = 0.65;
        opts.spaceMode = fileSpaceMode.Value;
        opts.spaceMix = fileSpaceMix.Value;
        config = buildRealtimeConfig(fileVoice.Value, opts);
        config.audio.normalizeInput = true;
        config.audio.removeDC = true;
        fileProcessButton.Enable = 'off';
        fileProcessButton.Text = 'PROCESSING…';
        fileStatusLabel.Text = 'Processing through the shared VoiceFX chain…';
        statusBadge.Text = '●  FILE PROCESSING';
        statusBadge.FontColor = C.orange;
        drawnow;
        tProcess = tic;
        try
            if strcmp(fileEngine.Value, 'hq')
                [fileProcessed, ~, fileDiagnostics] = processAudioFileHighQuality( ...
                    fileSource, fileFs, config);
            else
                [fileProcessed, ~] = processAudioFile(fileSource, fileFs, config);
                fileDiagnostics = struct('status','ok','engine','realtime-compatible');
            end
            elapsed = toc(tProcess);
            updateFilePlots(true);
            fileMetricProcess.Text = sprintf('%.2f s', elapsed);
            fileMetricRTF.Text = sprintf('%.3f', elapsed / max(numel(fileSource)/fileFs, eps));
            fileMetricPeak.Text = sprintf('%.1f dB', dashboardPeakDb(fileProcessed));
            fileStatusLabel.Text = sprintf('Done · %s · %s · %s · %s', ...
                fileEngine.Value, fileVoice.Value, fileFxMode.Value, fileSpaceMode.Value);
            statusBadge.Text = '●  FILE COMPLETE';
            statusBadge.FontColor = C.green;
        catch ME
            fileStatusLabel.Text = ['Processing error: ' ME.message];
            uialert(fig, ME.message, 'File processing error');
            statusBadge.Text = '●  SYSTEM READY';
            statusBadge.FontColor = C.green;
        end
        fileProcessButton.Enable = 'on';
        fileProcessButton.Text = '◆  PROCESS FILE';
    end

    function updateFilePlots(hasProcessed)
        if isempty(fileSource)
            return;
        end
        maxPlotSamples = min(numel(fileSource), round(5*fileFs));
        t = (0:maxPlotSamples-1).' / fileFs;
        cla(fileWaveAxes);
        plot(fileWaveAxes, t, fileSource(1:maxPlotSamples), ...
            'Color', C.cyan, 'LineWidth', 0.9);
        hold(fileWaveAxes, 'on');
        if hasProcessed && ~isempty(fileProcessed)
            n = min(maxPlotSamples, numel(fileProcessed));
            plot(fileWaveAxes, t(1:n), fileProcessed(1:n), ...
                'Color', C.purple, 'LineWidth', 1.0);
            legend(fileWaveAxes, {'Original','Processed'}, 'TextColor', C.text, ...
                'Color', C.card, 'EdgeColor', C.card2, 'Location', 'northeast');
        end

        [f0, db0] = dashboardSpectrum(fileSource, fileFs, 32768);
        cla(fileSpectrumAxes);
        plot(fileSpectrumAxes, f0, db0, 'Color', C.cyan, 'LineWidth', 1.0);
        hold(fileSpectrumAxes, 'on');
        if hasProcessed && ~isempty(fileProcessed)
            [f1, db1] = dashboardSpectrum(fileProcessed, fileFs, 32768);
            plot(fileSpectrumAxes, f1, db1, 'Color', C.purple, 'LineWidth', 1.1);
            legend(fileSpectrumAxes, {'Original','Processed'}, 'TextColor', C.text, ...
                'Color', C.card, 'EdgeColor', C.card2, 'Location', 'northeast');
        end
        xlim(fileSpectrumAxes, [0 min(16000, fileFs/2)]);
        ylim(fileSpectrumAxes, [-80 5]);
    end

    function onPlayFileOriginal(~, ~)
        if isempty(fileSource)
            onLoadFileSample([], []);
        end
        if ~isempty(fileSource)
            playDashboardAudio(fileSource, fileFs);
        end
    end

    function onPlayFileProcessed(~, ~)
        if isempty(fileProcessed)
            uialert(fig, 'Process the file first.', 'No processed audio');
            return;
        end
        playDashboardAudio(fileProcessed, fileFs);
    end

    function onSaveFile(~, ~)
        if isempty(fileProcessed)
            uialert(fig, 'Process the file before exporting.', 'No processed audio');
            return;
        end
        [name, folder] = uiputfile('voicefx_output.wav', 'Export processed WAV');
        if isequal(name, 0)
            return;
        end
        y = fileProcessed;
        peak = max(abs(y));
        if peak > 0.99
            y = 0.99 * y / peak;
        end
        try
            audiowrite(fullfile(folder, name), y, fileFs);
            fileStatusLabel.Text = ['Exported: ' fullfile(folder, name)];
        catch ME
            uialert(fig, ME.message, 'Export error');
        end
    end

    function playDashboardAudio(x, sourceFs)
        stopDashboardAudio();
        y = cleanDashboardAudio(x);
        if isempty(y)
            return;
        end
        peak = max(abs(y));
        if peak > 0.98
            y = 0.98 * y / peak;
        end
        try
            activePlayer = audioplayer(y, sourceFs);
            play(activePlayer);
        catch ME
            uialert(fig, ME.message, 'Audio playback error');
        end
    end

    function stopDashboardAudio()
        if ~isempty(activePlayer)
            try
                stop(activePlayer);
            catch
            end
        end
        activePlayer = [];
    end

    function onCloseFigure(~, ~)
        liveStopRequested = true;
        stopDashboardAudio();
        delete(fig);
    end

    function initializeSampleDropdowns()
        if isempty(samplePaths) || all(cellfun(@isempty, samplePaths))
            amSample.Items = {'No project samples'};
            amSample.ItemsData = {''};
            amSample.Value = '';
            fileSample.Items = {'No project samples'};
            fileSample.ItemsData = {''};
            fileSample.Value = '';
            return;
        end
        preferred = find(contains(lower(string(sampleNames)), 'spoken'), 1, 'first');
        if isempty(preferred)
            preferred = 1;
        end
        amSample.Value = samplePaths{preferred};
        fileSample.Value = samplePaths{preferred};
        loadFilePath(samplePaths{preferred});
    end
end

%% Local UI/data helpers --------------------------------------------------
function addTextLabel(layout, row, textValue, C)
label = uilabel(layout, 'Text', textValue, 'FontColor', C.muted, 'FontSize', 11);
label.Layout.Row = row;
label.Layout.Column = 1;
end

function styleAxes(ax, C, xLabelText, yLabelText)
ax.Color = C.card;
ax.XColor = C.muted;
ax.YColor = C.muted;
ax.GridColor = C.grid;
ax.MinorGridColor = C.grid;
ax.Box = 'off';
ax.FontSize = 10;
grid(ax, 'on');
xlabel(ax, xLabelText, 'Color', C.muted);
ylabel(ax, yLabelText, 'Color', C.muted);
end

function ax = cardAxes(parent, location, titleText, C, xLabelText, yLabelText)
panel = uipanel(parent, 'Title', titleText, 'ForegroundColor', C.text, ...
    'BackgroundColor', C.card, 'BorderType', 'none', 'FontWeight', 'bold');
panel.Layout.Row = location(1);
panel.Layout.Column = location(2);
axesLayout = uigridlayout(panel, [1 1]);
axesLayout.Padding = [8 8 8 8];
axesLayout.BackgroundColor = C.card;
ax = uiaxes(axesLayout);
styleAxes(ax, C, xLabelText, yLabelText);
end

function [valueLabel, titleLabel] = metricTile(parent, titleText, valueText, C)
panel = uipanel(parent, 'BackgroundColor', C.card, 'BorderType', 'none');
gridLayout = uigridlayout(panel, [2 1]);
gridLayout.RowHeight = {26, '1x'};
gridLayout.Padding = [10 8 10 8];
gridLayout.BackgroundColor = C.card;
titleLabel = uilabel(gridLayout, 'Text', titleText, 'FontColor', C.muted, ...
    'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
valueLabel = uilabel(gridLayout, 'Text', valueText, 'FontColor', C.text, ...
    'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
end

function [names, paths] = discoverSamples(sampleDir)
files = dir(fullfile(sampleDir, '*.wav'));
if isempty(files)
    names = {'No project samples'};
    paths = {''};
    return;
end
names = {files.name};
paths = cell(size(files));
for k = 1:numel(files)
    paths{k} = fullfile(files(k).folder, files(k).name);
end
end

function setDeviceDropdown(dropdown, devices)
items = [{'System default'}, devices(:).'];
data = [{''}, devices(:).'];
dropdown.Items = items;
dropdown.ItemsData = data;
dropdown.Value = '';
end

function value = onOff(tf)
if tf
    value = 'on';
else
    value = 'off';
end
end

function buffer = appendTail(buffer, frame, maxSamples)
buffer = [buffer(:); double(frame(:))]; %#ok<AGROW>
if numel(buffer) > maxSamples
    buffer = buffer(end-maxSamples+1:end);
end
end

function [frequency, magnitudeDb] = dashboardSpectrum(x, fs, maxNfft)
x = cleanDashboardAudio(x);
if isempty(x)
    frequency = zeros(0,1);
    magnitudeDb = zeros(0,1);
    return;
end
nfft = 2 ^ nextpow2(min(numel(x), maxNfft));
nfft = max(nfft, 256);
segment = x(1:min(numel(x), nfft));
if numel(segment) < nfft
    segment(end+1:nfft,1) = 0;
end
segment = segment - mean(segment);
if nfft > 1
    k = (0:nfft-1).';
    window = 0.5 - 0.5*cos(2*pi*k/(nfft-1));
else
    window = 1;
end
X = fft(segment .* window, nfft);
magnitude = abs(X(1:floor(nfft/2)+1));
magnitude = magnitude / max(max(magnitude), eps);
magnitudeDb = 20*log10(max(magnitude, 1e-4));
frequency = (0:numel(magnitude)-1).' * fs / nfft;
end

function x = cleanDashboardAudio(x)
x = double(x);
if isempty(x)
    x = zeros(0,1);
    return;
end
if ~isvector(x)
    x = mean(x, 2);
end
x = x(:);
x(~isfinite(x)) = 0;
end

function value = dashboardPeakDb(x)
x = cleanDashboardAudio(x);
if isempty(x)
    value = -Inf;
else
    value = 20*log10(max(max(abs(x)), 1e-8));
end
end
