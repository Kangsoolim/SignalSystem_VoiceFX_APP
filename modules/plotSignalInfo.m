function plotInfo = plotSignalInfo(varargin)
%PLOTSIGNALINFO Create basic waveform and spectrum figures for reports.
%   New interface:
%       plotInfo = plotSignalInfo(x, y, fs, plotConfig)
%   Legacy-compatible interface:
%       plotInfo = plotSignalInfo(target, x, y, fs, plotConfig)

[target, x, y, fs, plotConfig] = parseInputs(varargin{:});
plotConfig = fillDisplayDefaults(plotConfig);

x = cleanAudioVector(x);
y = cleanAudioVector(y);

plotInfo = struct();
plotInfo.input = analyzeSpectrum(x, fs, plotConfig);
plotInfo.output = analyzeSpectrum(y, fs, plotConfig);
plotInfo.fs = fs;
plotInfo.inputNumSamples = numel(x);
plotInfo.outputNumSamples = numel(y);
plotInfo.durationSeconds = max([numel(x), numel(y)]) / fs;
plotInfo.targetClass = class(target);
plotInfo.figureSaved = false;
plotInfo.figurePath = '';
plotInfo.outputDir = char(getDisplayOption(plotConfig, 'outputDir', fullfile('results', 'figures')));

if ~isTruthy(getDisplayOption(plotConfig, 'enabled', false)) && ...
        ~isTruthy(getDisplayOption(plotConfig, 'saveFigure', false))
    return;
end

fig = createSignalFigure(x, y, fs, plotConfig, plotInfo.input, plotInfo.output);

if isTruthy(getDisplayOption(plotConfig, 'saveFigure', false))
    outputDir = plotInfo.outputDir;
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    figureName = char(getDisplayOption(plotConfig, 'figureName', 'signal_info.png'));
    [~, ~, ext] = fileparts(figureName);
    if isempty(ext)
        figureName = [figureName, '.png'];
    end

    plotInfo.figurePath = fullfile(outputDir, figureName);
    if exist('exportgraphics', 'file') == 2
        exportgraphics(fig, plotInfo.figurePath, 'Resolution', 150);
    else
        saveas(fig, plotInfo.figurePath);
    end
    plotInfo.figureSaved = true;
end

close(fig);
end

function [target, x, y, fs, plotConfig] = parseInputs(varargin)
if nargin == 4
    target = [];
    x = varargin{1};
    y = varargin{2};
    fs = varargin{3};
    plotConfig = varargin{4};
elseif nargin >= 5
    target = varargin{1};
    x = varargin{2};
    y = varargin{3};
    fs = varargin{4};
    plotConfig = varargin{5};
elseif nargin == 3
    target = [];
    x = varargin{1};
    y = varargin{2};
    fs = varargin{3};
    plotConfig = struct();
else
    error('plotSignalInfo:InvalidInput', 'Expected plotSignalInfo(x, y, fs, config) or plotSignalInfo(target, x, y, fs, config).');
end

if isempty(plotConfig)
    plotConfig = struct();
end
end

function plotConfig = fillDisplayDefaults(plotConfig)
defaults = makeDefaultConfig();
defaultDisplay = defaults.display;
displayFields = fieldnames(defaultDisplay);
for k = 1:numel(displayFields)
    name = displayFields{k};
    if ~isfield(plotConfig, name)
        plotConfig.(name) = defaultDisplay.(name);
    end
end
end

function x = cleanAudioVector(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end

function fig = createSignalFigure(x, y, fs, plotConfig, xSpec, ySpec)
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Signal Info');

maxDuration = double(getDisplayOption(plotConfig, 'maxDurationToPlot', 2));
if ~isfinite(maxDuration) || maxDuration <= 0
    maxDuration = inf;
end

xPlotCount = min(numel(x), max(0, floor(maxDuration * fs)));
yPlotCount = min(numel(y), max(0, floor(maxDuration * fs)));
if isinf(maxDuration)
    xPlotCount = numel(x);
    yPlotCount = numel(y);
end

tx = (0:xPlotCount-1).' / fs;
ty = (0:yPlotCount-1).' / fs;

subplot(2, 2, 1);
plot(tx, x(1:xPlotCount), 'Color', [0.1, 0.35, 0.75]);
grid on;
xlabel('Time (s)');
ylabel('Amplitude');
title('Input Waveform');

subplot(2, 2, 2);
plot(ty, y(1:yPlotCount), 'Color', [0.7, 0.2, 0.15]);
grid on;
xlabel('Time (s)');
ylabel('Amplitude');
title('Output Waveform');

useDb = isTruthy(getDisplayOption(plotConfig, 'useDb', true));
subplot(2, 2, 3);
plotSpectrumAxes(xSpec, useDb, [0.1, 0.35, 0.75]);
title('Input Spectrum');

subplot(2, 2, 4);
plotSpectrumAxes(ySpec, useDb, [0.7, 0.2, 0.15]);
title('Output Spectrum');
end

function plotSpectrumAxes(specInfo, useDb, color)
if isempty(specInfo.f)
    plot(0, 0, 'Color', color);
else
    if useDb
        plot(specInfo.f, specInfo.magDb, 'Color', color);
        ylabel('Magnitude (dB)');
    else
        plot(specInfo.f, specInfo.mag, 'Color', color);
        ylabel('Magnitude');
    end
end
grid on;
xlabel('Frequency (Hz)');
end

function value = getDisplayOption(plotConfig, fieldName, defaultValue)
if isfield(plotConfig, fieldName) && ~isempty(plotConfig.(fieldName))
    value = plotConfig.(fieldName);
else
    value = defaultValue;
end
end

function tf = isTruthy(value)
if islogical(value) || isnumeric(value)
    tf = any(value(:) ~= 0);
else
    tf = strcmpi(char(value), 'true') || strcmpi(char(value), 'on') || strcmpi(char(value), 'yes');
end
end
