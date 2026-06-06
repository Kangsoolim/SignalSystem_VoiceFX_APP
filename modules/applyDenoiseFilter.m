function [yFrame, state] = applyDenoiseFilter(xFrame, fs, filterConfig, state)
%APPLYDENOISEFILTER Apply conservative traditional denoise filters.
%   Supported modes are none, highpass, lowpass, bandpass, notch50, and
%   voice_enhance. The default path uses filter with state continuity so the
%   same module can be shared by file and realtime processing.

if nargin < 3 || isempty(filterConfig)
    filterConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
filterConfig = fillFilterDefaults(filterConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'filter') || isempty(state.filter)
    state.filter = struct();
end

yFrame = double(xFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;

if ~isfield(filterConfig, 'enabled') || ~filterConfig.enabled
    return;
end

filterType = getFilterType(filterConfig);
if strcmpi(filterType, 'none') || isempty(yFrame)
    return;
end

if isempty(fs) || ~isfinite(fs) || fs <= 0
    yFrame(~isfinite(yFrame)) = 0;
    return;
end

[b, a, signature] = designStageFilter(filterType, fs, filterConfig);
if isempty(b) || isempty(a)
    return;
end

useZeroPhase = isTruthy(filterConfig.useZeroPhase);
minFiltFiltLength = 3 * max(numel(a), numel(b));
if useZeroPhase && exist('filtfilt', 'file') == 2 && numel(yFrame) > minFiltFiltLength
    yFrame = filtfilt(b, a, yFrame);
    state.filter.zi = [];
else
    ziLength = max(numel(a), numel(b)) - 1;
    if ziLength > 0
        if ~isfield(state.filter, 'signature') || ~strcmp(state.filter.signature, signature) || ...
                ~isfield(state.filter, 'zi') || numel(state.filter.zi) ~= ziLength
            state.filter.zi = zeros(ziLength, 1);
        end
        [yFrame, state.filter.zi] = filter(b, a, yFrame, state.filter.zi);
    else
        yFrame = filter(b, a, yFrame);
        state.filter.zi = [];
    end
end

yFrame = double(yFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;
state.filter.signature = signature;
state.filter.lastMode = filterType;
state.filter.lastFs = fs;
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

function filterType = getFilterType(filterConfig)
if isfield(filterConfig, 'type') && ~isempty(filterConfig.type)
    filterType = char(filterConfig.type);
elseif isfield(filterConfig, 'mode') && ~isempty(filterConfig.mode)
    filterType = char(filterConfig.mode);
else
    filterType = 'none';
end
end

function [b, a, signature] = designStageFilter(filterType, fs, filterConfig)
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

function tf = isTruthy(value)
if islogical(value) || isnumeric(value)
    tf = any(value(:) ~= 0);
else
    tf = strcmpi(char(value), 'true') || strcmpi(char(value), 'on') || strcmpi(char(value), 'yes');
end
end
