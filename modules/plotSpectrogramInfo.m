function plotInfo = plotSpectrogramInfo(varargin)
%PLOTSPECTROGRAMINFO Create report-ready input/output spectrogram figures.
%   New interface:
%       plotInfo = plotSpectrogramInfo(x, y, fs, plotConfig)
%   Legacy-compatible interface:
%       plotInfo = plotSpectrogramInfo(target, x, y, fs, plotConfig)

[target, x, y, fs, plotConfig] = parseInputs(varargin{:});
plotConfig = fillDisplayDefaults(plotConfig);

x = cleanAudioVector(x);
y = cleanAudioVector(y);

plotInfo = struct();
plotInfo.input = computeSpectrogramInfo(x, fs, plotConfig);
plotInfo.output = computeSpectrogramInfo(y, fs, plotConfig);
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

fig = createSpectrogramFigure(plotInfo.input, plotInfo.output);

if isTruthy(getDisplayOption(plotConfig, 'saveFigure', false))
    outputDir = plotInfo.outputDir;
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    figureName = char(getDisplayOption(plotConfig, 'figureName', 'spectrogram_info.png'));
    [~, ~, ext] = fileparts(figureName);
    if isempty(ext)
        figureName = [figureName, '.png'];
    end

    plotInfo.figurePath = fullfile(outputDir, figureName);
    saveFigure(fig, plotInfo.figurePath);
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
    error('plotSpectrogramInfo:InvalidInput', 'Expected plotSpectrogramInfo(x, y, fs, config) or plotSpectrogramInfo(target, x, y, fs, config).');
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

function spec = computeSpectrogramInfo(x, fs, plotConfig)
if isempty(fs) || ~isfinite(fs) || fs <= 0
    error('plotSpectrogramInfo:InvalidSampleRate', 'Sample rate must be positive.');
end

spec = struct();
spec.fs = fs;
spec.numSamples = numel(x);
spec.durationSeconds = numel(x) / fs;
spec.windowLength = getIntegerOption(plotConfig, 'spectrogramWindowLength', max(128, round(0.032 * fs)));
spec.overlapLength = getIntegerOption(plotConfig, 'spectrogramOverlapLength', round(0.75 * spec.windowLength));
spec.fftLength = getIntegerOption(plotConfig, 'spectrogramFftLength', 2 ^ nextpow2(spec.windowLength));
spec.dbFloor = double(getDisplayOption(plotConfig, 'dbFloor', -120));
spec.time = [];
spec.frequency = [];
spec.powerDb = [];

if isempty(x)
    return;
end

spec.windowLength = min(max(16, spec.windowLength), numel(x));
spec.overlapLength = min(max(0, spec.overlapLength), spec.windowLength - 1);
spec.fftLength = max(spec.windowLength, spec.fftLength);

[powerMatrix, f, t] = localStftPower(x, fs, spec.windowLength, spec.overlapLength, spec.fftLength);
spec.time = t;
spec.frequency = f;
spec.powerDb = 10 * log10(max(powerMatrix, 10 ^ (spec.dbFloor / 10)));
end

function [powerMatrix, f, t] = localStftPower(x, fs, windowLength, overlapLength, fftLength)
hopLength = max(1, windowLength - overlapLength);
if numel(x) < windowLength
    x(end + 1:windowLength, 1) = 0;
end

startIndices = 1:hopLength:(numel(x) - windowLength + 1);
if isempty(startIndices)
    startIndices = 1;
end

window = makeHannWindow(windowLength);
oneSidedCount = floor(fftLength / 2) + 1;
powerMatrix = zeros(oneSidedCount, numel(startIndices));

for k = 1:numel(startIndices)
    frame = x(startIndices(k):startIndices(k) + windowLength - 1) .* window;
    fftValues = fft(frame, fftLength);
    oneSided = fftValues(1:oneSidedCount);
    powerMatrix(:, k) = abs(oneSided) .^ 2 / max(sum(window .^ 2), eps);
end

f = (0:oneSidedCount-1).' * fs / fftLength;
t = (startIndices(:) + (windowLength - 1) / 2 - 1) / fs;
end

function window = makeHannWindow(windowLength)
n = (0:windowLength-1).';
if windowLength <= 1
    window = ones(windowLength, 1);
else
    window = 0.5 - 0.5 * cos(2 * pi * n / (windowLength - 1));
end
end

function fig = createSpectrogramFigure(inputSpec, outputSpec)
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Spectrogram Info');
set(fig, 'Position', [100, 100, 1100, 650]);

subplot(2, 1, 1);
plotSpectrogramAxes(inputSpec);
title('Input Spectrogram');

subplot(2, 1, 2);
plotSpectrogramAxes(outputSpec);
title('Output Spectrogram');
end

function plotSpectrogramAxes(spec)
if isempty(spec.time) || isempty(spec.frequency) || isempty(spec.powerDb)
    imagesc(0, 0, 0);
else
    imagesc(spec.time, spec.frequency / 1000, spec.powerDb);
end
axis xy;
grid on;
xlabel('Time (s)');
ylabel('Frequency (kHz)');
cb = colorbar;
ylabel(cb, 'Power (dB)');
end

function value = getDisplayOption(plotConfig, fieldName, defaultValue)
if isfield(plotConfig, fieldName) && ~isempty(plotConfig.(fieldName))
    value = plotConfig.(fieldName);
else
    value = defaultValue;
end
end

function value = getIntegerOption(plotConfig, fieldName, defaultValue)
value = getDisplayOption(plotConfig, fieldName, defaultValue);
value = round(abs(double(value)));
if isempty(value) || ~isfinite(value)
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

function saveFigure(fig, pathName)
if exist('exportgraphics', 'file') == 2
    exportgraphics(fig, pathName, 'Resolution', 180);
else
    saveas(fig, pathName);
end
end
