function responseInfo = plotFilterResponse(fs, filterConfig, plotConfig)
%PLOTFILTERRESPONSE Create a report-ready denoise filter response figure.
%   Filter coefficients are rebuilt with the same parameter rules used by
%   applyDenoiseFilter because its designStageFilter helper is private.

if nargin < 2 || isempty(filterConfig)
    filterConfig = struct('enabled', true, 'type', 'voice_enhance', 'params', struct());
end
if nargin < 3 || isempty(plotConfig)
    plotConfig = struct();
end

if isempty(fs) || ~isfinite(fs) || fs <= 0
    error('plotFilterResponse:InvalidSampleRate', 'Sample rate must be positive.');
end

filterConfig = fillFilterDefaults(filterConfig);
plotConfig = fillDisplayDefaults(plotConfig);
filterType = getFilterType(filterConfig);

[b, a, signature] = designStageFilterLikeApplyDenoiseFilter(filterType, fs, filterConfig);
if isempty(b) || isempty(a)
    error('plotFilterResponse:UnsupportedFilter', 'Unsupported filter type: %s.', filterType);
end

nfft = getIntegerOption(plotConfig, 'responseFftLength', 4096);
nfft = max(256, nfft);
[frequency, magnitudeDb, phaseRadians] = computeFrequencyResponse(b, a, fs, nfft);

responseInfo = struct();
responseInfo.fs = fs;
responseInfo.filterType = filterType;
responseInfo.b = b;
responseInfo.a = a;
responseInfo.signature = signature;
responseInfo.designNote = 'Coefficients are rebuilt with the same parameter defaults, clamps, Butterworth fallback, and notch formula used by applyDenoiseFilter.';
responseInfo.frequency = frequency;
responseInfo.magnitudeDb = magnitudeDb;
responseInfo.phaseRadians = phaseRadians;
responseInfo.figureSaved = false;
responseInfo.figurePath = '';
responseInfo.outputDir = char(getDisplayOption(plotConfig, 'outputDir', fullfile('results', 'figures')));

if ~isTruthy(getDisplayOption(plotConfig, 'enabled', false)) && ...
        ~isTruthy(getDisplayOption(plotConfig, 'saveFigure', false))
    return;
end

fig = createFilterResponseFigure(responseInfo);

if isTruthy(getDisplayOption(plotConfig, 'saveFigure', false))
    outputDir = responseInfo.outputDir;
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    defaultName = sprintf('filter_response_%s.png', sanitizeFilePart(filterType));
    figureName = char(getDisplayOption(plotConfig, 'figureName', defaultName));
    [~, ~, ext] = fileparts(figureName);
    if isempty(ext)
        figureName = [figureName, '.png'];
    end

    responseInfo.figurePath = fullfile(outputDir, figureName);
    saveFigure(fig, responseInfo.figurePath);
    responseInfo.figureSaved = true;
end

close(fig);
end

function filterConfig = fillFilterDefaults(filterConfig)
defaults = makeDefaultConfig();
defaultFilter = defaults.filter;
filterFields = fieldnames(defaultFilter);
for k = 1:numel(filterFields)
    name = filterFields{k};
    if ~isfield(filterConfig, name)
        filterConfig.(name) = defaultFilter.(name);
    end
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

function filterType = getFilterType(filterConfig)
if isfield(filterConfig, 'type') && ~isempty(filterConfig.type)
    filterType = char(filterConfig.type);
elseif isfield(filterConfig, 'mode') && ~isempty(filterConfig.mode)
    filterType = char(filterConfig.mode);
else
    filterType = 'none';
end
end

function [b, a, signature] = designStageFilterLikeApplyDenoiseFilter(filterType, fs, filterConfig)
nyquist = fs / 2;
order = getIntegerField(filterConfig, 'order', 4);
order = max(1, min(order, 8));

switch lower(filterType)
    case 'highpass'
        cutoff = getOptionalField(filterConfig, 'cutoff', []);
        if isempty(cutoff)
            cutoff = getOptionalField(filterConfig, 'lowCutoff', 80);
        end
        cutoff = clampFrequency(cutoff, nyquist, 80);
        [b, a] = designButter(order, cutoff / nyquist, 'high');

    case 'lowpass'
        cutoff = getOptionalField(filterConfig, 'cutoff', []);
        if isempty(cutoff)
            cutoff = getOptionalField(filterConfig, 'highCutoff', 3400);
        end
        cutoff = clampFrequency(cutoff, nyquist, min(3400, 0.45 * fs));
        [b, a] = designButter(order, cutoff / nyquist, 'low');

    case 'bandpass'
        lowCutoff = clampFrequency(getOptionalField(filterConfig, 'lowCutoff', 80), nyquist, 80);
        highCutoff = clampFrequency(getOptionalField(filterConfig, 'highCutoff', 3400), nyquist, min(3400, 0.45 * fs));
        [lowCutoff, highCutoff] = sortBand(lowCutoff, highCutoff, nyquist);
        [b, a] = designButter(order, [lowCutoff, highCutoff] / nyquist, 'bandpass');

    case 'notch50'
        notchFreq = clampFrequency(getOptionalField(filterConfig, 'notchFreq', 50), nyquist, 50);
        bandwidth = getOptionalField(filterConfig, 'bandwidth', 2);
        [b, a] = designNotch(notchFreq, bandwidth, fs);

    case 'voice_enhance'
        lowCutoff = clampFrequency(getOptionalField(filterConfig, 'lowCutoff', 80), nyquist, 80);
        highCutoff = clampFrequency(getOptionalField(filterConfig, 'highCutoff', 4000), nyquist, min(4000, 0.45 * fs));
        [lowCutoff, highCutoff] = sortBand(lowCutoff, highCutoff, nyquist);
        [b, a] = designButter(max(2, order), [lowCutoff, highCutoff] / nyquist, 'bandpass');

    otherwise
        b = [];
        a = [];
end

signature = sprintf('%s_fs%.6g_order%d_b%s_a%s', lower(filterType), fs, order, mat2str(b, 6), mat2str(a, 6));
end

function [b, a] = designButter(order, normalizedCutoff, filterKind)
normalizedCutoff = min(max(normalizedCutoff, 1e-6), 0.999999);
if exist('butter', 'file') == 2
    [b, a] = butter(order, normalizedCutoff, filterKind);
else
    [b, a] = designFallbackFirstOrder(normalizedCutoff, filterKind);
end
end

function [b, a] = designFallbackFirstOrder(normalizedCutoff, filterKind)
alpha = min(max(normalizedCutoff(1), 1e-6), 0.999999);
switch lower(filterKind)
    case 'high'
        b = [(1 + alpha) / 2, -(1 + alpha) / 2];
        a = [1, -alpha];
    otherwise
        b = 1 - alpha;
        a = [1, -alpha];
end
end

function [b, a] = designNotch(notchFreq, bandwidth, fs)
bandwidth = max(0.5, abs(double(bandwidth)));
w0 = 2 * pi * notchFreq / fs;
r = 1 - pi * bandwidth / fs;
r = min(max(r, 0.80), 0.9999);

b = [1, -2 * cos(w0), 1];
a = [1, -2 * r * cos(w0), r ^ 2];
dcGain = sum(a) / sum(b);
if isfinite(dcGain) && abs(sum(b)) > eps
    b = b * dcGain;
end
end

function [lowCutoff, highCutoff] = sortBand(lowCutoff, highCutoff, nyquist)
lowCutoff = min(lowCutoff, nyquist * 0.95);
highCutoff = min(highCutoff, nyquist * 0.98);
if highCutoff <= lowCutoff
    lowCutoff = max(1, min(lowCutoff, nyquist * 0.45));
    highCutoff = min(nyquist * 0.98, max(lowCutoff + 1, nyquist * 0.8));
end
end

function value = clampFrequency(value, nyquist, defaultValue)
if isempty(value) || ~isfinite(double(value))
    value = defaultValue;
end
value = abs(double(value));
if value <= 0
    value = defaultValue;
end
value = min(max(value, 1), nyquist * 0.98);
end

function value = getOptionalField(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function value = getIntegerField(s, fieldName, defaultValue)
value = getOptionalField(s, fieldName, defaultValue);
value = round(abs(double(value)));
if isempty(value) || ~isfinite(value)
    value = defaultValue;
end
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

function [frequency, magnitudeDb, phaseRadians] = computeFrequencyResponse(b, a, fs, nfft)
frequency = linspace(0, fs / 2, floor(nfft / 2) + 1).';
omega = 2 * pi * frequency / fs;

b = b(:).';
a = a(:).';
numerator = zeros(size(omega));
denominator = zeros(size(omega));

for k = 1:numel(b)
    numerator = numerator + b(k) * exp(-1i * omega * (k - 1));
end
for k = 1:numel(a)
    denominator = denominator + a(k) * exp(-1i * omega * (k - 1));
end

denominator(abs(denominator) < eps) = eps;
h = numerator ./ denominator;
magnitudeDb = 20 * log10(max(abs(h), 1e-12));
phaseRadians = unwrap(angle(h));
end

function fig = createFilterResponseFigure(responseInfo)
fig = figure('Visible', 'off', 'Color', 'w', 'Name', ['Filter Response ', responseInfo.filterType]);
set(fig, 'Position', [100, 100, 1000, 620]);

subplot(2, 1, 1);
plot(responseInfo.frequency, responseInfo.magnitudeDb, 'LineWidth', 1.2, 'Color', [0.1, 0.35, 0.75]);
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title(sprintf('%s Magnitude Response', formatFilterName(responseInfo.filterType)));
xlim([0, responseInfo.fs / 2]);

subplot(2, 1, 2);
plot(responseInfo.frequency, responseInfo.phaseRadians, 'LineWidth', 1.0, 'Color', [0.7, 0.2, 0.15]);
grid on;
xlabel('Frequency (Hz)');
ylabel('Phase (rad)');
title(sprintf('%s Phase Response', formatFilterName(responseInfo.filterType)));
xlim([0, responseInfo.fs / 2]);
end

function label = formatFilterName(filterType)
text = regexprep(strrep(lower(char(filterType)), '_', ' '), '([a-z])([0-9])', '$1 $2');
parts = strsplit(strtrim(text));
for k = 1:numel(parts)
    if ~isempty(parts{k})
        parts{k} = [upper(parts{k}(1)), parts{k}(2:end)];
    end
end
label = strjoin(parts, ' ');
end

function filePart = sanitizeFilePart(value)
filePart = lower(regexprep(char(value), '[^a-zA-Z0-9_-]+', '_'));
if isempty(filePart)
    filePart = 'filter';
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
