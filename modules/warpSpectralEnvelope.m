function [yFrame, state] = warpSpectralEnvelope(xFrame, fs, voiceConfig, state)
%WARPSPECTRALENVELOPE Coarse stateful spectral-envelope warping.
%   The signal is decomposed into eight causal bands. The smoothed band
%   envelope is sampled on a warped log-frequency axis, then bounded gains
%   are applied and temporally smoothed. This changes broad resonant-envelope
%   placement without restarting phase at frame boundaries.

x = cleanColumn(xFrame);
yFrame = x;
if isempty(x)
    return;
end
if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'voice') || isempty(state.voice)
    state.voice = struct();
end
if isempty(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('warpSpectralEnvelope:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

scale = getParam(voiceConfig, 'formantScale', ...
    getParam(voiceConfig, 'formantScaleHint', 1.0));
scale = clamp(double(scale), 0.78, 1.28);
strength = clamp01(getParam(voiceConfig, 'envelopeWarpStrength', 0.65));
maxGainDb = clamp(double(getParam(voiceConfig, 'envelopeWarpMaxGainDb', 6.0)), 1, 10);

if abs(scale - 1) < 0.01 || strength <= 0.001
    return;
end

cutoffs = makeCutoffs(fs);
numBands = numel(cutoffs) + 1;
if ~isfield(state.voice, 'envelopeWarp') || isempty(state.voice.envelopeWarp)
    state.voice.envelopeWarp = struct();
end
ew = state.voice.envelopeWarp;
if ~isfield(ew, 'lpPrev') || numel(ew.lpPrev) ~= numel(cutoffs)
    ew.lpPrev = zeros(numel(cutoffs), 1);
end

lowSignals = cell(numel(cutoffs), 1);
for k = 1:numel(cutoffs)
    [lowSignals{k}, ew.lpPrev(k)] = onePoleLowpass( ...
        x, fs, cutoffs(k), ew.lpPrev(k));
end
bands = cell(numBands, 1);
bands{1} = lowSignals{1};
for k = 2:numel(cutoffs)
    bands{k} = lowSignals{k} - lowSignals{k-1};
end
bands{numBands} = x - lowSignals{end};

bandRms = zeros(numBands, 1);
for k = 1:numBands
    bandRms(k) = sqrt(mean(bands{k}.^2) + eps);
end
envelopeDb = 20 * log10(bandRms + eps);
envelopeDb = smoothAcrossBands(envelopeDb);
centers = bandCenters(cutoffs, fs);

queryFreq = centers / scale;
queryFreq = min(max(queryFreq, centers(1)), centers(end));
targetDb = interp1(log(centers), envelopeDb, ...
    log(queryFreq), 'linear');

gainDb = strength * (targetDb - envelopeDb);
gainDb = min(max(gainDb, -maxGainDb), maxGainDb);
targetGain = 10 .^ (gainDb / 20);

if ~isfield(ew, 'gain') || numel(ew.gain) ~= numBands || ...
        any(~isfinite(ew.gain))
    ew.gain = ones(numBands, 1);
end
frameSeconds = numel(x) / fs;
tau = max(getParam(voiceConfig, 'envelopeWarpSmoothingTime', 0.10), 0.02);
alpha = exp(-frameSeconds / tau);
ew.gain = alpha * ew.gain + (1-alpha) * targetGain;

yFrame = zeros(size(x));
for k = 1:numBands
    yFrame = yFrame + ew.gain(k) * bands{k};
end

% Limited energy preservation prevents broad-envelope warping from becoming
% an accidental loudness effect.
inRms = sqrt(mean(x.^2));
outRms = sqrt(mean(yFrame.^2));
if inRms > 1e-7 && outRms > 1e-7
    correction = clamp(inRms / outRms, 10^(-1.5/20), 10^(1.5/20));
    yFrame = yFrame * correction;
end

state.voice.envelopeWarp = ew;
yFrame = cleanColumn(yFrame);
end

function cutoffs = makeCutoffs(fs)
base = [180, 350, 700, 1200, 2000, 3200, 4800];
limit = 0.42 * fs;
cutoffs = min(base, limit);
for k = 2:numel(cutoffs)
    if cutoffs(k) <= cutoffs(k-1)
        cutoffs(k) = min(limit, cutoffs(k-1) + max(20, 0.01*fs));
    end
end
end

function centers = bandCenters(cutoffs, fs)
numBands = numel(cutoffs) + 1;
centers = zeros(numBands, 1);
centers(1) = max(60, cutoffs(1)/2);
for k = 2:numel(cutoffs)
    centers(k) = sqrt(cutoffs(k-1) * cutoffs(k));
end
centers(end) = sqrt(cutoffs(end) * min(0.46*fs, fs/2-1));
for k = 2:numel(centers)
    if centers(k) <= centers(k-1)
        centers(k) = centers(k-1) + 1;
    end
end
end

function y = smoothAcrossBands(x)
kernel = [1; 2; 3; 2; 1] / 9;
y = conv(x, kernel, 'same');
% Edge correction for the two outermost bins.
if numel(x) >= 2
    y(1) = 0.75*x(1) + 0.25*x(2);
    y(end) = 0.75*x(end) + 0.25*x(end-1);
end
end

function [y, prev] = onePoleLowpass(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2*pi*cutoff/fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1-alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end

function value = getParam(config, name, defaultValue)
if isstruct(config) && isfield(config, 'params') && ...
        isstruct(config.params) && isfield(config.params, name) && ...
        ~isempty(config.params.(name))
    value = config.params.(name);
else
    value = defaultValue;
end
end

function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end
function value = clamp01(value)
value = clamp(value, 0, 1);
end
function x = cleanColumn(x)
x = double(x(:));
x(~isfinite(x)) = 0;
end
