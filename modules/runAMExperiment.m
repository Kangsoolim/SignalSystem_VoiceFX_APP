function result = runAMExperiment(x, fs, options)
%RUNAMEXPERIMENT Complete AM transmit-channel-receive experiment for Dashboard.
%   RESULT = RUNAMEXPERIMENT(X, FS, OPTIONS) performs conventional DSB-LC
%   amplitude modulation, optional additive white Gaussian noise, coherent
%   product detection, causal lowpass recovery, gain alignment, and a set of
%   report-friendly metrics/spectra.
%
%   OPTIONS fields (all optional):
%       carrierFreq              transmitter carrier frequency in Hz
%       modulationIndex          AM modulation index, default 0.7
%       messageScale             normalized message peak, default 0.8
%       lowpassCutoff            receiver LPF cutoff in Hz, default 3400
%       filterOrder              Butterworth order, default 4
%       channelSnrDb             AWGN SNR in dB, Inf disables noise
%       receiverFreqOffsetHz     coherent receiver frequency error in Hz
%       receiverPhaseOffsetDeg   coherent receiver phase error in degrees
%       initialPhase             transmitter phase in radians
%       experimentSeed           local deterministic noise seed
%
%   The function uses applyModDemod for transmitter and receiver processing
%   so the AM Lab and the framework share one algorithm implementation.

if nargin < 3 || isempty(options)
    options = struct();
end
if isempty(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('runAMExperiment:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

message = cleanMono(x);
if isempty(message)
    error('runAMExperiment:EmptyInput', 'Input signal must not be empty.');
end
message = message - mean(message);
peak = max(abs(message));
if peak > eps
    message = 0.95 * message / peak;
end

baseConfig = makeDefaultConfig();
defaults = baseConfig.modDemod;
lowpassCutoff = positiveScalar(readOption(options, 'lowpassCutoff', ...
    defaults.lowpassCutoff), defaults.lowpassCutoff);
lowpassCutoff = min(max(lowpassCutoff, 40), 0.42 * fs);

% Keep enough guard band for conventional AM sidebands while adapting to
% low-rate source files. This prevents an invalid carrier/cutoff combination
% from silently aliasing in the lab.
nyquist = fs / 2;
carrierDefault = min(defaults.carrierFreq, 0.32 * fs);
carrierFreq = positiveScalar(readOption(options, 'carrierFreq', ...
    carrierDefault), carrierDefault);
maxCarrier = max(1, nyquist - 1.05 * lowpassCutoff);
minCarrier = min(maxCarrier, max(1.10 * lowpassCutoff, 100));
if maxCarrier <= 100
    lowpassCutoff = max(40, 0.18 * fs);
    maxCarrier = max(1, nyquist - 1.05 * lowpassCutoff);
    minCarrier = min(maxCarrier, max(1.10 * lowpassCutoff, 100));
end
carrierFreq = min(max(carrierFreq, minCarrier), maxCarrier);
if carrierFreq >= nyquist
    carrierFreq = 0.35 * fs;
end

modulationIndex = finiteScalar(readOption(options, 'modulationIndex', ...
    defaults.modulationIndex), defaults.modulationIndex);
modulationIndex = min(max(abs(modulationIndex), 0), 1.5);
messageScale = finiteScalar(readOption(options, 'messageScale', ...
    defaults.messageScale), defaults.messageScale);
messageScale = min(max(abs(messageScale), 0.05), 1.0);
filterOrder = round(positiveScalar(readOption(options, 'filterOrder', ...
    defaults.filterOrder), defaults.filterOrder));
filterOrder = min(max(filterOrder, 1), 8);
initialPhase = finiteScalar(readOption(options, 'initialPhase', ...
    defaults.initialPhase), defaults.initialPhase);
channelSnrDb = readOption(options, 'channelSnrDb', defaults.channelSnrDb);
channelSnrDb = finiteOrInf(channelSnrDb, Inf);
receiverFreqOffsetHz = finiteScalar(readOption(options, ...
    'receiverFreqOffsetHz', 0), 0);
receiverPhaseOffsetDeg = finiteScalar(readOption(options, ...
    'receiverPhaseOffsetDeg', 0), 0);
experimentSeed = round(finiteScalar(readOption(options, ...
    'experimentSeed', defaults.experimentSeed), defaults.experimentSeed));

% Transmitter: conventional DSB-LC AM through the shared module.
txConfig = defaults;
txConfig.enabled = true;
txConfig.type = 'am_modulate';
txConfig.mode = 'am_modulate';
txConfig.carrierFreq = carrierFreq;
txConfig.initialPhase = initialPhase;
txConfig.modulationIndex = modulationIndex;
txConfig.messageScale = messageScale;
txConfig.normalizeOutput = false;
[modulated, ~] = applyModDemod(message, fs, txConfig, []);

% Deterministic local AWGN generation does not change MATLAB's global RNG.
[channelSignal, measuredChannelSnrDb] = addAwgnLocal( ...
    modulated, channelSnrDb, experimentSeed);

% Receiver: coherent product detection with independently controllable LO.
rxConfig = defaults;
rxConfig.enabled = true;
rxConfig.type = 'am_demodulate';
rxConfig.mode = 'am_demodulate';
rxConfig.carrierFreq = carrierFreq;
rxConfig.receiverCarrierFreq = carrierFreq + receiverFreqOffsetHz;
rxConfig.receiverPhase = initialPhase + receiverPhaseOffsetDeg * pi / 180;
rxConfig.lowpassCutoff = lowpassCutoff;
rxConfig.filterOrder = filterOrder;
rxConfig.normalizeOutput = false;
[~, demodulatedRaw] = applyModDemod(channelSignal, fs, rxConfig, []);

% Remove filter transient from metric fitting, then find one least-squares
% gain so AM carrier scaling does not dominate reconstruction quality scores.
[demodulated, metricRange, alignmentGain, alignmentLagSamples] = alignRecovered( ...
    message, demodulatedRaw, fs, filterOrder, lowpassCutoff);
metrics = computeMetrics(message, demodulated, metricRange);
metrics.alignmentGain = alignmentGain;
metrics.alignmentLagSamples = alignmentLagSamples;
metrics.alignmentLagMs = 1000 * alignmentLagSamples / fs;
metrics.channelSnrTargetDb = channelSnrDb;
metrics.channelSnrMeasuredDb = measuredChannelSnrDb;
metrics.modulationIndex = modulationIndex;
metrics.envelopeMinimum = 1 - modulationIndex * messageScale;
metrics.overmodulated = metrics.envelopeMinimum < 0;
metrics.basebandBandwidthHz = estimateBandwidth(message, fs, 0.995);
metrics.estimatedAMBandwidthHz = min(fs, 2 * metrics.basebandBandwidthHz);
metrics.receiverFrequencyHz = rxConfig.receiverCarrierFreq;
metrics.receiverFrequencyOffsetHz = receiverFreqOffsetHz;
metrics.receiverPhaseOffsetDeg = receiverPhaseOffsetDeg;

result = struct();
result.fs = fs;
result.time = (0:numel(message)-1).' / fs;
result.original = message;
result.modulated = modulated;
result.channel = channelSignal;
result.demodulatedRaw = demodulatedRaw;
result.demodulated = demodulated;
result.envelope = analyticEnvelope(modulated);
result.txConfig = txConfig;
result.rxConfig = rxConfig;
result.options = options;
result.metricRange = metricRange;
result.metrics = metrics;
result.spectra = struct();
result.spectra.original = makeSpectrum(message, fs);
result.spectra.modulated = makeSpectrum(modulated, fs);
result.spectra.channel = makeSpectrum(channelSignal, fs);
result.spectra.demodulated = makeSpectrum(demodulated, fs);
end

function [y, measuredSnrDb] = addAwgnLocal(x, targetSnrDb, seed)
x = cleanMono(x);
if isinf(targetSnrDb) && targetSnrDb > 0
    y = x;
    measuredSnrDb = Inf;
    return;
end
signalPower = mean(x .^ 2);
if signalPower <= eps
    y = x;
    measuredSnrDb = Inf;
    return;
end
noisePower = signalPower / (10 ^ (targetSnrDb / 10));
stream = RandStream('mt19937ar', 'Seed', max(0, seed));
noise = sqrt(noisePower) * randn(stream, size(x));
y = x + noise;
actualNoisePower = mean(noise .^ 2);
measuredSnrDb = 10 * log10(signalPower / max(actualNoisePower, eps));
end

function [aligned, metricRange, gain, lagSamples] = alignRecovered(reference, recovered, fs, order, cutoff)
reference = cleanMono(reference);
recovered = cleanMono(recovered);
n = min(numel(reference), numel(recovered));
reference = reference(1:n);
recovered = recovered(1:n);
recovered = recovered - mean(recovered);

settleSeconds = max(0.035, 4 * order / max(cutoff, 40));
startIndex = min(n, max(1, round(settleSeconds * fs) + 1));
metricRange = startIndex:n;
if isempty(metricRange)
    metricRange = 1:n;
end

% Estimate only the small causal receiver delay. A bounded FFT correlation
% avoids hiding gross synchronization errors or coherent-frequency mismatch.
fitEnd = min(n, startIndex + round(3 * fs) - 1);
refFit = reference(startIndex:fitEnd);
recFit = recovered(startIndex:fitEnd);
lagSamples = estimateBoundedLag(recFit, refFit, round(0.02 * fs));
recovered = compensateLag(recovered, lagSamples);

edgeGuard = abs(lagSamples);
metricStart = min(n, startIndex + edgeGuard);
metricEnd = max(metricStart, n - edgeGuard);
metricRange = metricStart:metricEnd;
refValid = reference(metricRange);
recValid = recovered(metricRange);
denominator = dot(recValid, recValid);
if denominator > eps
    gain = dot(recValid, refValid) / denominator;
else
    gain = 1;
end
aligned = gain * recovered;
end

function lag = estimateBoundedLag(signal, reference, maxLag)
signal = cleanMono(signal);
reference = cleanMono(reference);
n = min(numel(signal), numel(reference));
if n < 4
    lag = 0;
    return;
end
signal = signal(1:n) - mean(signal(1:n));
reference = reference(1:n) - mean(reference(1:n));
fullLength = 2 * n - 1;
nfft = 2 ^ nextpow2(fullLength);
correlation = ifft(fft(signal, nfft) .* fft(flipud(reference), nfft));
correlation = real(correlation(1:fullLength));
lags = (-(n-1):(n-1)).';
maxLag = min(max(0, round(maxLag)), n-1);
mask = abs(lags) <= maxLag;
restricted = abs(correlation(mask));
restrictedLags = lags(mask);
[~, index] = max(restricted);
lag = restrictedLags(index);
end

function shifted = compensateLag(signal, lag)
signal = cleanMono(signal);
n = numel(signal);
shifted = zeros(size(signal));
if lag > 0
    shifted(1:n-lag) = signal(1+lag:n);
elseif lag < 0
    advance = -lag;
    shifted(1+advance:n) = signal(1:n-advance);
else
    shifted = signal;
end
end

function metrics = computeMetrics(reference, estimate, metricRange)
reference = cleanMono(reference);
estimate = cleanMono(estimate);
n = min(numel(reference), numel(estimate));
reference = reference(1:n);
estimate = estimate(1:n);
metricRange = metricRange(metricRange >= 1 & metricRange <= n);
if isempty(metricRange)
    metricRange = 1:n;
end
r = reference(metricRange);
y = estimate(metricRange);
r = r - mean(r);
y = y - mean(y);
errorSignal = r - y;
referencePower = mean(r .^ 2);
errorPower = mean(errorSignal .^ 2);
metrics = struct();
metrics.reconstructionSnrDb = 10 * log10(max(referencePower, eps) / ...
    max(errorPower, eps));
metrics.nmse = sum(errorSignal .^ 2) / max(sum(r .^ 2), eps);
denominator = sqrt(sum(r .^ 2) * sum(y .^ 2));
if denominator > eps
    metrics.correlation = dot(r, y) / denominator;
else
    metrics.correlation = 0;
end
metrics.outputPeak = max(abs(estimate));
metrics.outputRms = sqrt(mean(estimate .^ 2));
end

function bandwidth = estimateBandwidth(x, fs, energyFraction)
x = cleanMono(x);
if isempty(x) || all(abs(x) < eps)
    bandwidth = 0;
    return;
end
maxNfft = 65536;
nfft = 2 ^ nextpow2(min(numel(x), maxNfft));
nfft = max(nfft, 256);
segment = x(1:min(numel(x), nfft));
if numel(segment) < nfft
    segment(end+1:nfft, 1) = 0;
end
window = cosineWindow(nfft);
X = fft(segment .* window, nfft);
powerOneSided = abs(X(1:floor(nfft/2)+1)) .^ 2;
powerOneSided(1) = 0;
totalEnergy = sum(powerOneSided);
if totalEnergy <= eps
    bandwidth = 0;
    return;
end
cumulative = cumsum(powerOneSided) / totalEnergy;
index = find(cumulative >= energyFraction, 1, 'first');
if isempty(index)
    index = numel(powerOneSided);
end
frequency = (0:numel(powerOneSided)-1).' * fs / nfft;
bandwidth = frequency(index);
end

function envelope = analyticEnvelope(x)
x = cleanMono(x);
if exist('hilbert', 'file') == 2
    envelope = abs(hilbert(x));
    return;
end
% Toolbox-free visualization fallback: local RMS envelope.
windowLength = max(5, round(numel(x) / 500));
windowLength = min(windowLength, 401);
kernel = ones(windowLength, 1) / windowLength;
envelope = sqrt(max(filter(kernel, 1, x .^ 2), 0));
end

function spectrum = makeSpectrum(x, fs)
x = cleanMono(x);
maxNfft = 65536;
nfft = 2 ^ nextpow2(min(numel(x), maxNfft));
nfft = max(nfft, 256);
segment = x(1:min(numel(x), nfft));
if numel(segment) < nfft
    segment(end+1:nfft, 1) = 0;
end
segment = segment - mean(segment);
window = cosineWindow(nfft);
X = fft(segment .* window, nfft);
magnitude = abs(X(1:floor(nfft/2)+1));
magnitude = magnitude / max(max(magnitude), eps);
spectrum = struct();
spectrum.frequency = (0:numel(magnitude)-1).' * fs / nfft;
spectrum.magnitude = magnitude;
spectrum.magnitudeDb = 20 * log10(max(magnitude, 1e-6));
end

function window = cosineWindow(n)
if n <= 1
    window = ones(max(n, 1), 1);
else
    k = (0:n-1).';
    window = 0.5 - 0.5 * cos(2 * pi * k / (n - 1));
end
end

function value = readOption(options, fieldName, defaultValue)
if isstruct(options) && isfield(options, fieldName) && ...
        ~isempty(options.(fieldName))
    value = options.(fieldName);
else
    value = defaultValue;
end
end

function value = finiteScalar(value, fallback)
value = double(value);
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = fallback;
end
end

function value = positiveScalar(value, fallback)
value = abs(finiteScalar(value, fallback));
if value <= 0
    value = fallback;
end
end

function value = finiteOrInf(value, fallback)
value = double(value);
if isempty(value) || ~isscalar(value) || isnan(value)
    value = fallback;
elseif ~isfinite(value) && value < 0
    value = fallback;
end
end

function x = cleanMono(x)
x = double(x);
if isempty(x)
    x = zeros(0, 1);
    return;
end
if ~isvector(x)
    x = mean(x, 2);
end
x = x(:);
x(~isfinite(x)) = 0;
end
