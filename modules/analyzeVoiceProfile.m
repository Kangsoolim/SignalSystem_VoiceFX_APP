function profile = analyzeVoiceProfile(x, fs, options)
%ANALYZEVOICEPROFILE Build a richer source-voice acoustic profile.
%   profile = analyzeVoiceProfile(x, fs)
%   profile = analyzeVoiceProfile(x, fs, options)
%
%   Intended use:
%       1) Analyze a short calibration utterance (about 1-5 s).
%       2) Build a stable user voice profile.
%       3) Feed the profile to adaptVoiceStyleConfig.
%
%   This function deliberately separates:
%       - pitch/F0 statistics
%       - energy and dynamic-range statistics
%       - speech activity / pause / rhythm proxies
%       - spectral and harmonicity statistics
%       - optional LPC formant estimates (when lpc is available)
%
%   Important:
%   energyOnsetRateHz and energyModulationRateHz are rhythm/speaking-rate
%   proxies, NOT true syllable rate or phoneme rate. Accent and articulation
%   cannot be identified reliably from these summary DSP features alone.

if nargin < 3 || isempty(options)
    options = struct();
end

validateattributes(fs, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'fs');

x = double(x);
if isempty(x)
    x = zeros(0, 1);
elseif ~isvector(x)
    x = robustProfileDownmix(x);
end
x = x(:);
x(~isfinite(x)) = 0;

opts = fillDefaults(options, fs);
profile = emptyProfile(fs, numel(x));

if isempty(x)
    profile.status = 'empty';
    return;
end

profile.duration = numel(x) / fs;
profile.rmsLevel = sqrt(mean(x .^ 2));
profile.peakLevel = max(abs(x));
profile.dcOffset = mean(x);
profile.crestFactorDb = 20 * log10((profile.peakLevel + eps) / ...
    (profile.rmsLevel + eps));

frameLength = max(64, round(opts.frameDuration * fs));
hopLength = max(1, round(opts.hopDuration * fs));

if numel(x) < frameLength
    x = [x; zeros(frameLength - numel(x), 1)];
end

numFrames = 1 + floor((numel(x) - frameLength) / hopLength);
profile.frameCount = numFrames;

window = 0.5 - 0.5 * cos(2 * pi * (0:frameLength-1).' / ...
    max(frameLength - 1, 1));

nfft = 2 ^ nextpow2(frameLength);
freq = (0:(nfft/2)).' * fs / nfft;

frameRms = zeros(numFrames, 1);
frameZcr = zeros(numFrames, 1);
centroid = nan(numFrames, 1);
spread = nan(numFrames, 1);
rolloff85 = nan(numFrames, 1);
flatness = nan(numFrames, 1);
lowRatio = nan(numFrames, 1);
midRatio = nan(numFrames, 1);
highRatio = nan(numFrames, 1);

f0Values = nan(numFrames, 1);
confidenceValues = zeros(numFrames, 1);

formant1 = nan(numFrames, 1);
formant2 = nan(numFrames, 1);
formant3 = nan(numFrames, 1);
canEstimateFormants = exist('lpc', 'file') == 2;

minLag = max(1, floor(fs / opts.maxF0));
maxLag = min(frameLength - 3, ceil(fs / opts.minF0));

for frameIndex = 1:numFrames
    firstSample = 1 + (frameIndex - 1) * hopLength;
    lastSample = firstSample + frameLength - 1;

    frame = x(firstSample:lastSample);
    frame = frame - mean(frame);

    frameRms(frameIndex) = sqrt(mean(frame .^ 2));
    frameZcr(frameIndex) = mean(abs(diff(frame >= 0))) / 2;

    windowed = frame .* window;
    spectrum = fft(windowed, nfft);
    powerSpec = abs(spectrum(1:nfft/2+1)) .^ 2;
    powerSum = sum(powerSpec) + eps;

    centroid(frameIndex) = sum(freq .* powerSpec) / powerSum;
    spread(frameIndex) = sqrt(sum(((freq - centroid(frameIndex)) .^ 2) .* ...
        powerSpec) / powerSum);

    cumulativePower = cumsum(powerSpec);
    rolloffIndex = find(cumulativePower >= opts.rolloffPercent * ...
        cumulativePower(end), 1, 'first');
    if isempty(rolloffIndex)
        rolloffIndex = numel(freq);
    end
    rolloff85(frameIndex) = freq(rolloffIndex);

    positivePower = powerSpec + eps;
    flatness(frameIndex) = exp(mean(log(positivePower))) / ...
        mean(positivePower);

    [lowRatio(frameIndex), midRatio(frameIndex), highRatio(frameIndex)] = ...
        bandEnergyRatios(powerSpec, freq, fs);

    if minLag < maxLag && frameRms(frameIndex) >= opts.minRms
        [f0Values(frameIndex), confidenceValues(frameIndex)] = ...
            estimateF0Autocorr(windowed, fs, minLag, maxLag, ...
            opts.minConfidence, opts.minF0, opts.maxF0);
    end

    if canEstimateFormants && mod(frameIndex - 1, opts.formantStride) == 0 && ...
            frameRms(frameIndex) >= opts.minRms
        formants = estimateFormantsLpc(frame, fs, opts);
        if numel(formants) >= 1, formant1(frameIndex) = formants(1); end
        if numel(formants) >= 2, formant2(frameIndex) = formants(2); end
        if numel(formants) >= 3, formant3(frameIndex) = formants(3); end
    end
end

% Remove isolated octave-tracking jumps before summary statistics. This
% keeps source adaptation stable for high, low and mixed-register speakers.
f0Values = correctOctaveErrors(f0Values, confidenceValues, ...
    frameRms, opts);

% ---------- Speech activity and pause/rhythm profile ----------
sortedRms = sort(frameRms);
rmsP90 = percentileSorted(sortedRms, 90);
speechThreshold = max(opts.minRms, opts.speechThresholdRatio * rmsP90);
activityMask = frameRms >= speechThreshold;

minSpeechFrames = max(1, round(opts.minSpeechDuration / opts.hopDuration));
minPauseFrames = max(1, round(opts.minPauseDuration / opts.hopDuration));

activityMask = removeShortTrueRuns(activityMask, minSpeechFrames);
activityMask = fillShortFalseRuns(activityMask, minPauseFrames);

profile.speechActivityRatio = mean(activityMask);
profile.pauseRatio = 1 - profile.speechActivityRatio;

[speechStarts, speechLengths] = trueRuns(activityMask);
[pauseStarts, pauseLengths] = trueRuns(~activityMask);

% Edge silence is not treated as an internal speaking pause.
if ~isempty(pauseStarts)
    internalPause = pauseStarts > 1 & ...
        (pauseStarts + pauseLengths - 1) < numFrames;
    pauseLengths = pauseLengths(internalPause);
end

profile.speechSegmentCount = numel(speechLengths);
profile.pauseCount = numel(pauseLengths);
profile.energyOnsetRateHz = profile.speechSegmentCount / ...
    max(profile.duration, eps);

if isempty(pauseLengths)
    profile.meanPauseDuration = 0;
    profile.medianPauseDuration = 0;
else
    pauseDurations = pauseLengths * opts.hopDuration;
    profile.meanPauseDuration = mean(pauseDurations);
    profile.medianPauseDuration = median(pauseDurations);
end

if numel(speechStarts) >= 3
    onsetIntervals = diff(speechStarts) * opts.hopDuration;
    profile.rhythmIntervalCv = std(onsetIntervals) / ...
        max(mean(onsetIntervals), eps);
else
    profile.rhythmIntervalCv = NaN;
end

profile.energyModulationRateHz = estimateEnergyModulationRate( ...
    frameRms, opts.hopDuration, opts);

% ---------- Energy statistics ----------
speechRms = frameRms(activityMask);
if isempty(speechRms)
    speechRms = frameRms;
end

speechRmsDb = 20 * log10(speechRms + eps);
sortedSpeechRmsDb = sort(speechRmsDb);

profile.rmsFrameMedian = median(speechRms);
profile.rmsFrameStd = std(speechRms);
profile.energyP10Db = percentileSorted(sortedSpeechRmsDb, 10);
profile.energyP50Db = percentileSorted(sortedSpeechRmsDb, 50);
profile.energyP90Db = percentileSorted(sortedSpeechRmsDb, 90);
profile.dynamicRangeDb = profile.energyP90Db - profile.energyP10Db;

% ---------- F0 / pitch contour statistics ----------
validF0Mask = isfinite(f0Values) & ...
    f0Values >= opts.minF0 & f0Values <= opts.maxF0 & activityMask;
validF0 = f0Values(validF0Mask);
validConfidence = confidenceValues(validF0Mask);

profile.voicedFrameCount = numel(validF0);
profile.voicedRatio = profile.voicedFrameCount / max(profile.frameCount, 1);
profile.voicedRatioOfSpeech = profile.voicedFrameCount / ...
    max(sum(activityMask), 1);
profile.f0Track = f0Values;
profile.confidenceTrack = confidenceValues;

if isempty(validF0)
    profile.status = 'unvoiced';
else
    sortedF0 = sort(validF0);

    profile.f0Median = median(validF0);
    profile.f0Mean = mean(validF0);
    profile.f0Low = percentileSorted(sortedF0, 10);
    profile.f0P25 = percentileSorted(sortedF0, 25);
    profile.f0P75 = percentileSorted(sortedF0, 75);
    profile.f0High = percentileSorted(sortedF0, 90);
    profile.f0Range = profile.f0High - profile.f0Low;
    profile.f0Iqr = profile.f0P75 - profile.f0P25;
    profile.f0Std = std(validF0);
    profile.f0Cv = profile.f0Std / max(profile.f0Mean, eps);

    if profile.f0Low > 0 && profile.f0High > profile.f0Low
        profile.pitchRangeSemitones = 12 * log2( ...
            profile.f0High / profile.f0Low);
    else
        profile.pitchRangeSemitones = 0;
    end

    f0Diff = abs(diff(validF0));
    if isempty(f0Diff)
        profile.f0DeltaMedian = 0;
        profile.f0DeltaP90 = 0;
    else
        sortedDiff = sort(f0Diff);
        profile.f0DeltaMedian = median(f0Diff);
        profile.f0DeltaP90 = percentileSorted(sortedDiff, 90);
    end

    profile.confidenceMean = mean(validConfidence);
    profile.harmonicityProxy = profile.confidenceMean;
    profile.status = 'ok';
end

% ---------- Spectral summary over active speech frames ----------
specMask = activityMask;
if ~any(specMask)
    specMask = true(numFrames, 1);
end

profile.zcrMedian = median(frameZcr(specMask));
profile.spectralCentroidMean = meanFinite(centroid(specMask));
profile.spectralCentroidMedian = medianFinite(centroid(specMask));
profile.spectralSpreadMean = meanFinite(spread(specMask));
profile.spectralRolloff85Mean = meanFinite(rolloff85(specMask));
profile.spectralFlatnessMean = meanFinite(flatness(specMask));
profile.lowBandEnergyRatio = meanFinite(lowRatio(specMask));
profile.midBandEnergyRatio = meanFinite(midRatio(specMask));
profile.highBandEnergyRatio = meanFinite(highRatio(specMask));

% Optional formant estimates. NaN means LPC was unavailable or unreliable.
profile.formant1Median = medianFinite(formant1);
profile.formant2Median = medianFinite(formant2);
profile.formant3Median = medianFinite(formant3);
profile.formantMethod = ternary(canEstimateFormants, 'lpc_optional', 'unavailable');

% Raw tracks kept for diagnostics/visualization.
profile.frameRmsTrack = frameRms;
profile.activityMask = activityMask;
profile.spectralCentroidTrack = centroid;
profile.spectralFlatnessTrack = flatness;
end

% -------------------------------------------------------------------------
function mono = robustProfileDownmix(x)
channelRms = sqrt(mean(double(x).^2,1));
[dominantRms, dominantIndex] = max(channelRms);
weightSum = sum(channelRms);
if weightSum <= eps
    mono = mean(x,2);
else
    weights = channelRms/weightSum;
    mono = double(x)*weights(:);
    monoRms = sqrt(mean(mono.^2));
    if dominantRms > eps && monoRms < 0.30*dominantRms
        mono = double(x(:,dominantIndex));
    end
end
mono = mono(:);
mono(~isfinite(mono)) = 0;
end

function corrected = correctOctaveErrors(f0, confidence, frameRms, opts)
corrected = f0(:);
valid = isfinite(corrected) & corrected >= opts.minF0 & ...
    corrected <= opts.maxF0 & confidence(:) >= opts.minConfidence;

if ~any(valid)
    return;
end

% Ignore the quietest frames when choosing the reference register.
rmsThreshold = percentileSorted(sort(frameRms(:)), 35);
seedMask = valid & frameRms(:) >= rmsThreshold;
if ~any(seedMask)
    seedMask = valid;
end
reference = median(corrected(seedMask));
if ~isfinite(reference) || reference <= 0
    return;
end

for k = 1:numel(corrected)
    value = corrected(k);
    if ~isfinite(value) || value <= 0
        continue;
    end

    candidates = [value/2, value, value*2];
    allowed = candidates >= opts.minF0 & candidates <= opts.maxF0;
    candidates = candidates(allowed);
    if isempty(candidates)
        continue;
    end

    distance = abs(log2(candidates/reference));
    [bestDistance, bestIndex] = min(distance);
    originalDistance = abs(log2(value/reference));

    % Only correct a clear octave mistake. Genuine expressive excursions are
    % left untouched.
    if originalDistance > 0.72 && bestDistance < 0.38 && ...
            candidates(bestIndex) ~= value
        corrected(k) = candidates(bestIndex);
    end
end

% Short robust smoothing removes one-frame jumps without flattening the
% utterance contour used by diagnostics.
halfWindow = 2;
smoothed = corrected;
for k = 1:numel(corrected)
    first = max(1,k-halfWindow);
    last = min(numel(corrected),k+halfWindow);
    values = corrected(first:last);
    values = values(isfinite(values));
    if numel(values) >= 3 && isfinite(corrected(k))
        localMedian = median(values);
        if abs(log2(corrected(k)/localMedian)) > 0.55
            smoothed(k) = localMedian;
        end
    end
end
corrected = smoothed;
end

% -------------------------------------------------------------------------
function opts = fillDefaults(options, fs)
opts = struct();
opts.frameDuration = getField(options, 'frameDuration', 0.040);
opts.hopDuration = getField(options, 'hopDuration', 0.010);
opts.minF0 = getField(options, 'minF0', 60);
opts.maxF0 = getField(options, 'maxF0', 450);
opts.minRms = getField(options, 'minRms', 1e-4);
opts.minConfidence = getField(options, 'minConfidence', 0.35);
opts.speechThresholdRatio = getField(options, 'speechThresholdRatio', 0.18);
opts.minSpeechDuration = getField(options, 'minSpeechDuration', 0.06);
opts.minPauseDuration = getField(options, 'minPauseDuration', 0.10);
opts.rolloffPercent = getField(options, 'rolloffPercent', 0.85);
opts.minRhythmHz = getField(options, 'minRhythmHz', 0.5);
opts.maxRhythmHz = getField(options, 'maxRhythmHz', 8.0);
opts.formantStride = max(1, round(getField(options, 'formantStride', 3)));
opts.formantMaxHz = getField(options, 'formantMaxHz', min(5000, 0.45 * fs));
opts.maxFormantBandwidth = getField(options, 'maxFormantBandwidth', 700);

opts.frameDuration = max(0.020, double(opts.frameDuration));
opts.hopDuration = max(0.001, double(opts.hopDuration));
opts.minF0 = max(40, double(opts.minF0));
opts.maxF0 = max(opts.minF0 + 10, double(opts.maxF0));
opts.minRms = max(0, double(opts.minRms));
opts.minConfidence = min(max(double(opts.minConfidence), 0), 1);
opts.speechThresholdRatio = min(max(double(opts.speechThresholdRatio), 0.01), 1);
opts.rolloffPercent = min(max(double(opts.rolloffPercent), 0.50), 0.99);
end

function profile = emptyProfile(fs, inputLength)
nanValue = NaN;
profile = struct( ...
    'status', 'uninitialized', ...
    'sampleRate', double(fs), ...
    'inputLength', double(inputLength), ...
    'duration', 0, ...
    'rmsLevel', 0, ...
    'peakLevel', 0, ...
    'dcOffset', 0, ...
    'crestFactorDb', nanValue, ...
    'frameCount', 0, ...
    'speechActivityRatio', 0, ...
    'pauseRatio', 1, ...
    'speechSegmentCount', 0, ...
    'pauseCount', 0, ...
    'meanPauseDuration', 0, ...
    'medianPauseDuration', 0, ...
    'energyOnsetRateHz', 0, ...
    'energyModulationRateHz', nanValue, ...
    'rhythmIntervalCv', nanValue, ...
    'rmsFrameMedian', 0, ...
    'rmsFrameStd', 0, ...
    'energyP10Db', nanValue, ...
    'energyP50Db', nanValue, ...
    'energyP90Db', nanValue, ...
    'dynamicRangeDb', nanValue, ...
    'voicedFrameCount', 0, ...
    'voicedRatio', 0, ...
    'voicedRatioOfSpeech', 0, ...
    'f0Median', nanValue, ...
    'f0Mean', nanValue, ...
    'f0Low', nanValue, ...
    'f0P25', nanValue, ...
    'f0P75', nanValue, ...
    'f0High', nanValue, ...
    'f0Range', nanValue, ...
    'f0Iqr', nanValue, ...
    'f0Std', nanValue, ...
    'f0Cv', nanValue, ...
    'pitchRangeSemitones', nanValue, ...
    'f0DeltaMedian', nanValue, ...
    'f0DeltaP90', nanValue, ...
    'confidenceMean', nanValue, ...
    'harmonicityProxy', nanValue, ...
    'zcrMedian', nanValue, ...
    'spectralCentroidMean', nanValue, ...
    'spectralCentroidMedian', nanValue, ...
    'spectralSpreadMean', nanValue, ...
    'spectralRolloff85Mean', nanValue, ...
    'spectralFlatnessMean', nanValue, ...
    'lowBandEnergyRatio', nanValue, ...
    'midBandEnergyRatio', nanValue, ...
    'highBandEnergyRatio', nanValue, ...
    'formant1Median', nanValue, ...
    'formant2Median', nanValue, ...
    'formant3Median', nanValue, ...
    'formantMethod', 'unavailable', ...
    'f0Track', zeros(0, 1), ...
    'confidenceTrack', zeros(0, 1), ...
    'frameRmsTrack', zeros(0, 1), ...
    'activityMask', false(0, 1), ...
    'spectralCentroidTrack', zeros(0, 1), ...
    'spectralFlatnessTrack', zeros(0, 1));
end

function [f0, confidence] = estimateF0Autocorr(frame, fs, minLag, maxLag, ...
        minConfidence, minF0, maxF0)
f0 = NaN;
confidence = 0;

lags = (minLag:maxLag).';
scores = zeros(size(lags));

for k = 1:numel(lags)
    lag = lags(k);
    a = frame(1:end-lag);
    b = frame(1+lag:end);
    denom = sqrt(sum(a .^ 2) * sum(b .^ 2)) + eps;
    scores(k) = sum(a .* b) / denom;
end

[bestScore, bestIdx] = max(scores);
if ~isfinite(bestScore) || bestScore < minConfidence
    return;
end

% Sub-sample lag refinement reduces the integer-lag quantization error that
% is especially visible at higher F0. A three-point parabolic interpolation
% is used around the strongest normalized-autocorrelation peak.
refinedLag = double(lags(bestIdx));
if bestIdx > 1 && bestIdx < numel(scores)
    y1 = scores(bestIdx - 1);
    y2 = scores(bestIdx);
    y3 = scores(bestIdx + 1);
    denominator = y1 - 2 * y2 + y3;
    if isfinite(denominator) && abs(denominator) > 1e-12
        delta = 0.5 * (y1 - y3) / denominator;
        delta = min(max(delta, -0.5), 0.5);
        refinedLag = refinedLag + delta;
    end
end

candidateF0 = fs / max(refinedLag, eps);
if candidateF0 >= minF0 && candidateF0 <= maxF0
    f0 = candidateF0;
    confidence = bestScore;
end
end

function [lowRatio, midRatio, highRatio] = bandEnergyRatios(powerSpec, freq, fs)
nyquist = fs / 2;
total = sum(powerSpec) + eps;

lowMask = freq >= 80 & freq < min(500, nyquist);
midMask = freq >= 500 & freq < min(2000, nyquist);
highMask = freq >= 2000 & freq <= min(8000, nyquist);

lowRatio = sum(powerSpec(lowMask)) / total;
midRatio = sum(powerSpec(midMask)) / total;
highRatio = sum(powerSpec(highMask)) / total;
end

function rateHz = estimateEnergyModulationRate(frameRms, hopDuration, opts)
if numel(frameRms) < 8
    rateHz = NaN;
    return;
end

env = frameRms(:) - mean(frameRms);
nfft = 2 ^ nextpow2(numel(env));
spec = abs(fft(env, nfft)) .^ 2;
modFs = 1 / hopDuration;
f = (0:nfft-1).' * modFs / nfft;

valid = f >= opts.minRhythmHz & f <= opts.maxRhythmHz;
if ~any(valid)
    rateHz = NaN;
    return;
end

validIndices = find(valid);
[~, localIndex] = max(spec(valid));
rateHz = f(validIndices(localIndex));
end

function formants = estimateFormantsLpc(frame, fs, opts)
formants = zeros(0, 1);
try
    preEmphasized = filter([1 -0.97], 1, frame);
    order = max(8, round(2 + fs / 1000));
    a = lpc(preEmphasized, order);
    rootsA = roots(a);
    rootsA = rootsA(imag(rootsA) > 0);

    frequencies = angle(rootsA) * fs / (2 * pi);
    bandwidths = -(fs / pi) * log(abs(rootsA));

    valid = frequencies > 90 & ...
        frequencies < opts.formantMaxHz & ...
        bandwidths > 0 & bandwidths < opts.maxFormantBandwidth;

    frequencies = sort(frequencies(valid));
    formants = frequencies(1:min(3, numel(frequencies)));
catch
    formants = zeros(0, 1);
end
end

function mask = removeShortTrueRuns(mask, minLength)
[starts, lengths] = trueRuns(mask);
for k = 1:numel(starts)
    if lengths(k) < minLength
        mask(starts(k):starts(k)+lengths(k)-1) = false;
    end
end
end

function mask = fillShortFalseRuns(mask, maxGapLength)
[starts, lengths] = trueRuns(~mask);
for k = 1:numel(starts)
    runStart = starts(k);
    runEnd = runStart + lengths(k) - 1;
    isInternal = runStart > 1 && runEnd < numel(mask);
    if isInternal && lengths(k) <= maxGapLength
        mask(runStart:runEnd) = true;
    end
end
end

function [starts, lengths] = trueRuns(mask)
mask = logical(mask(:));
edges = diff([false; mask; false]);
starts = find(edges == 1);
ends = find(edges == -1) - 1;
lengths = ends - starts + 1;
end

function value = percentileSorted(sortedValues, percentile)
n = numel(sortedValues);
if n == 0
    value = NaN;
    return;
elseif n == 1
    value = sortedValues(1);
    return;
end

position = 1 + (n - 1) * (double(percentile) / 100);
lowerIndex = floor(position);
upperIndex = ceil(position);

if lowerIndex == upperIndex
    value = sortedValues(lowerIndex);
else
    fraction = position - lowerIndex;
    value = sortedValues(lowerIndex) * (1 - fraction) + ...
        sortedValues(upperIndex) * fraction;
end
end

function value = meanFinite(x)
x = x(isfinite(x));
if isempty(x), value = NaN; else, value = mean(x); end
end

function value = medianFinite(x)
x = x(isfinite(x));
if isempty(x), value = NaN; else, value = median(x); end
end

function value = getField(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function out = ternary(condition, trueValue, falseValue)
if condition, out = trueValue; else, out = falseValue; end
end
