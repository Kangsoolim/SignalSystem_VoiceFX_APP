function [y, diagnostics] = warpSpectralEnvelopeHQ(x, fs, voiceConfig)
%WARPSPECTRALENVELOPEHQ Offline cepstral spectral-envelope warping.
%   [y, diagnostics] = warpSpectralEnvelopeHQ(x, fs, voiceConfig)
%
%   This full-file stage estimates a smooth log-spectral envelope in each
%   overlapping STFT frame, samples that envelope on a warped frequency
%   axis, and applies only the bounded envelope-ratio gain. Harmonic phase
%   is preserved. The operation therefore changes broad vocal-tract color
%   more directly than the old eight-band EQ-like warp, while avoiding the
%   frame-reset pitch artifacts that occurred in early realtime prototypes.
%
%   The realtime/frame path still uses warpSpectralEnvelope.m. This function
%   is intentionally for loaded-file quality processing.

if nargin < 3 || isempty(voiceConfig)
    defaults = makeDefaultConfig();
    voiceConfig = defaults.voice;
end

x = finiteColumn(x);
diagnostics = struct( ...
    'status', 'ok', ...
    'formantScale', 1, ...
    'strength', 0, ...
    'maxGainDb', 0, ...
    'frameLength', 0, ...
    'hopLength', 0, ...
    'cepstralOrder', 0, ...
    'meanAbsoluteGainDb', 0, ...
    'maxAbsoluteGainDb', 0);

if isempty(x)
    y = x;
    diagnostics.status = 'empty';
    return;
end
validateattributes(fs, {'numeric'}, ...
    {'scalar','real','finite','positive'}, mfilename, 'fs');

scale = getParam(voiceConfig, 'formantScale', ...
    getParam(voiceConfig, 'formantScaleHint', 1.0));
scale = clamp(scale, 0.84, 1.32);
strength = clamp01(getParam(voiceConfig, 'envelopeWarpStrength', 0.65));
maxGainDb = clamp(getParam(voiceConfig, 'envelopeWarpMaxGainDb', 4.5), 1, 8);
tau = clamp(getParam(voiceConfig, 'envelopeWarpSmoothingTime', 0.10), ...
    0.03, 0.30);
cepOrder = round(clamp(getParam(voiceConfig, 'hqCepstralOrder', 40), 12, 100));

diagnostics.formantScale = scale;
diagnostics.strength = strength;
diagnostics.maxGainDb = maxGainDb;

if abs(scale-1) < 0.01 || strength < 0.005
    y = x;
    diagnostics.status = 'bypass';
    return;
end

frameLength = chooseFrameLength(fs, numel(x));
hopLength = max(1, round(frameLength/4));
cepOrder = min(cepOrder, floor(frameLength/4)-1);
window = sqrtPeriodicHann(frameLength);

diagnostics.frameLength = frameLength;
diagnostics.hopLength = hopLength;
diagnostics.cepstralOrder = cepOrder;

% Symmetric padding gives the first and last speech segments the same overlap
% support as interior frames.
padLength = frameLength;
xPad = [zeros(padLength,1); x; zeros(padLength,1)];
numFrames = max(1, ceil((numel(xPad)-frameLength)/hopLength)+1);
requiredLength = (numFrames-1)*hopLength + frameLength;
if numel(xPad) < requiredLength
    xPad(end+1:requiredLength,1) = 0;
end

yAccum = zeros(requiredLength,1);
normAccum = zeros(requiredLength,1);
prevGainDb = zeros(frameLength/2+1,1);
alpha = exp(-(hopLength/fs)/tau);

freq = (0:frameLength/2).' * fs/frameLength;
frequencyWeight = makeFrequencyWeight(freq, fs);
meanGainAccumulator = 0;
maxGainObserved = 0;

for frameIndex = 1:numFrames
    firstSample = 1 + (frameIndex-1)*hopLength;
    lastSample = firstSample + frameLength - 1;

    frame = xPad(firstSample:lastSample) .* window;
    spectrum = fft(frame, frameLength);
    magnitude = max(abs(spectrum), 1e-10);
    logMagnitude = log(magnitude);

    cepstrum = real(ifft(logMagnitude));
    liftered = zeros(size(cepstrum));
    liftered(1:cepOrder+1) = cepstrum(1:cepOrder+1);
    liftered(end-cepOrder+1:end) = cepstrum(end-cepOrder+1:end);

    envelopeLog = real(fft(liftered));
    envelopePositive = envelopeLog(1:frameLength/2+1);

    queryFrequency = freq / scale;
    queryFrequency = min(max(queryFrequency, freq(1)), freq(end));
    warpedEnvelope = interp1(freq, envelopePositive, ...
        queryFrequency, 'linear', 'extrap');

    rawGainDb = (warpedEnvelope-envelopePositive) * 20/log(10);
    rawGainDb = strength .* frequencyWeight .* rawGainDb;
    rawGainDb = min(max(rawGainDb, -maxGainDb), maxGainDb);

    smoothGainDb = alpha*prevGainDb + (1-alpha)*rawGainDb;
    prevGainDb = smoothGainDb;

    gainPositive = 10.^(smoothGainDb/20);
    gainFull = [gainPositive; gainPositive(end-1:-1:2)];
    shapedSpectrum = spectrum .* gainFull;

    frameOut = real(ifft(shapedSpectrum)) .* window;
    yAccum(firstSample:lastSample) = ...
        yAccum(firstSample:lastSample) + frameOut;
    normAccum(firstSample:lastSample) = ...
        normAccum(firstSample:lastSample) + window.^2;

    meanGainAccumulator = meanGainAccumulator + mean(abs(smoothGainDb));
    maxGainObserved = max(maxGainObserved, max(abs(smoothGainDb)));
end

validNorm = normAccum > 1e-10;
yAccum(validNorm) = yAccum(validNorm) ./ normAccum(validNorm);
yAccum(~validNorm) = 0;

firstOriginal = padLength + 1;
y = yAccum(firstOriginal:firstOriginal+numel(x)-1);
y = limitedRmsMatch(y, x, 1.2);
y = finiteColumn(y);

diagnostics.meanAbsoluteGainDb = meanGainAccumulator/max(numFrames,1);
diagnostics.maxAbsoluteGainDb = maxGainObserved;
end

function n = chooseFrameLength(fs, signalLength)
target = round(0.042*fs);
n = 2^nextpow2(max(target, 256));
n = min(max(n, 512), 2048);
while n > signalLength && n > 256
    n = n/2;
end
n = max(256, round(n));
end

function w = sqrtPeriodicHann(n)
index = (0:n-1).';
periodicHann = 0.5 - 0.5*cos(2*pi*index/n);
w = sqrt(max(periodicHann, 0));
end

function weight = makeFrequencyWeight(freq, fs)
% Do not strongly reshape sub-rumble energy or very-high sibilant/noise bins.
weight = ones(size(freq));
lowRamp = min(max(freq/180, 0.20), 1.0);
weight = weight .* lowRamp;

highStart = min(5000, 0.28*fs);
highEnd = min(10000, 0.45*fs);
if highEnd > highStart
    highFraction = min(max((freq-highStart)/(highEnd-highStart), 0), 1);
    weight = weight .* (1 - 0.75*highFraction);
end
end

function y = limitedRmsMatch(y, reference, maxCorrectionDb)
y = finiteColumn(y);
reference = finiteColumn(reference);
rmsY = sqrt(mean(y.^2));
rmsRef = sqrt(mean(reference.^2));
if rmsY <= 1e-8 || rmsRef <= 1e-8
    return;
end
maxGain = 10^(abs(maxCorrectionDb)/20);
gain = clamp(rmsRef/rmsY, 1/maxGain, maxGain);
y = y*gain;
end

function value = getParam(config, name, defaultValue)
if isstruct(config) && isfield(config, 'params') && ...
        isstruct(config.params) && isfield(config.params, name) && ...
        ~isempty(config.params.(name))
    value = double(config.params.(name));
else
    value = double(defaultValue);
end
end

function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end
function value = clamp01(value)
value = clamp(value, 0, 1);
end
function x = finiteColumn(x)
x = double(x(:));
x(~isfinite(x)) = 0;
end
