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

if strcmpi(filterType, 'speech_clean')
    [yFrame, state] = applySpeechClean(yFrame, fs, filterConfig, state);
    yFrame = double(yFrame(:));
    yFrame(~isfinite(yFrame)) = 0;
    state.filter.signature = sprintf('speech_clean_fs%.6g', fs);
    state.filter.lastMode = filterType;
    state.filter.lastFs = fs;
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
            cutoff = getOptionalField(filterConfig, 'lowpassCutoff', getOptionalField(filterConfig, 'highCutoff', 2700));
        end
        cutoff = clampFrequency(cutoff, nyquist, min(3400, 0.45 * fs));
        [b, a] = designButter(order, cutoff / nyquist, 'low');

    case 'bandpass'
        lowCutoff = clampFrequency(getOptionalField(filterConfig, 'bandpassLowCutoff', getOptionalField(filterConfig, 'lowCutoff', 150)), nyquist, 150);
        highCutoff = clampFrequency(getOptionalField(filterConfig, 'bandpassHighCutoff', getOptionalField(filterConfig, 'highCutoff', 3600)), nyquist, min(3600, 0.45 * fs));
        [lowCutoff, highCutoff] = sortBand(lowCutoff, highCutoff, nyquist);
        [b, a] = designButter(order, [lowCutoff, highCutoff] / nyquist, 'bandpass');

    case 'notch50'
        notchFreq = clampFrequency(getOptionalField(filterConfig, 'notchFreq', 50), nyquist, 50);
        bandwidth = getOptionalField(filterConfig, 'bandwidth', 2);
        [b, a] = designNotch(notchFreq, bandwidth, fs);

    case 'voice_enhance'
        lowCutoff = clampFrequency(getOptionalField(filterConfig, 'voiceLowCutoff', getOptionalField(filterConfig, 'lowCutoff', 95)), nyquist, 95);
        highCutoff = clampFrequency(getOptionalField(filterConfig, 'voiceHighCutoff', getOptionalField(filterConfig, 'highCutoff', 4800)), nyquist, min(4800, 0.45 * fs));
        [lowCutoff, highCutoff] = sortBand(lowCutoff, highCutoff, nyquist);
        [b, a] = designButter(max(2, min(order, 3)), [lowCutoff, highCutoff] / nyquist, 'bandpass');

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


function [y, state] = applySpeechClean(x, fs, cfg, state)
%APPLYSPEECHCLEAN VAD-aware causal speech enhancement.
%   Chain:
%       rumble/DC suppression
%       -> narrow mains-hum notch bank
%       -> frame-level speech probability estimate
%       -> eight-band noise tracking
%       -> Wiener-like gain with VAD-dependent update rate
%       -> attack/release smoothing
%       -> limited RMS compensation
%
%   This is an interpretable DSP enhancer. It does not claim to reproduce a
%   neural enhancement model, but it borrows the engineering principles of
%   perceptually distributed bands, temporal context and conservative gain
%   smoothing.

if ~isfield(state.filter, 'speechClean') || isempty(state.filter.speechClean)
    state.filter.speechClean = struct();
end
sc = state.filter.speechClean;

% 1) Rumble/DC suppression.
nyquist = fs / 2;
lowCutoff = clampFrequency(getOptionalField(cfg, ...
    'speechCleanLowCutoff', 70), nyquist, 70);
[bHp, aHp] = designButter(2, lowCutoff / nyquist, 'high');
[y, sc.hpZi] = runIirWithState(x, bHp, aHp, getStructField(sc, 'hpZi', []));

% 2) Narrow power-line interference removal.
mainsFreq = abs(double(getOptionalField(cfg, 'mainsFreq', ...
    getOptionalField(cfg, 'notchFreq', 50))));
numHarmonics = max(0, round(getOptionalField(cfg, 'mainsHarmonics', 4)));
bandwidth = max(0.5, double(getOptionalField(cfg, 'mainsBandwidth', 1.5)));
if ~isfield(sc, 'notchZi') || ~iscell(sc.notchZi) || ...
        numel(sc.notchZi) ~= numHarmonics
    sc.notchZi = cell(numHarmonics, 1);
end
for h = 1:numHarmonics
    f0 = h * mainsFreq;
    if f0 >= 1 && f0 < 0.45 * fs
        [bN, aN] = designNotch(f0, bandwidth, fs);
        [y, sc.notchZi{h}] = runIirWithState( ...
            y, bN, aN, sc.notchZi{h});
    end
end

% 3) Speech probability. The estimate combines relative energy, spectral
% flatness and zero-crossing behavior. Hangover smoothing prevents speech
% onsets/offsets from abruptly changing the denoiser state.
[speechProb, sc] = estimateSpeechProbability(y, fs, cfg, sc);

% 4) Eight-band causal decomposition.
cutoffs = makeSpeechCleanCutoffs(fs);
numBands = numel(cutoffs) + 1;
if ~isfield(sc, 'lpPrev') || numel(sc.lpPrev) ~= numel(cutoffs)
    sc.lpPrev = zeros(numel(cutoffs), 1);
end
lowSignals = cell(numel(cutoffs), 1);
for k = 1:numel(cutoffs)
    [lowSignals{k}, sc.lpPrev(k)] = onePoleLowpassState( ...
        y, fs, cutoffs(k), sc.lpPrev(k));
end
bands = cell(numBands, 1);
bands{1} = lowSignals{1};
for k = 2:numel(cutoffs)
    bands{k} = lowSignals{k} - lowSignals{k-1};
end
bands{numBands} = y - lowSignals{end};

bandPower = zeros(numBands, 1);
for k = 1:numBands
    bandPower(k) = mean(bands{k}.^2) + eps;
end
if ~isfield(sc, 'noisePower') || numel(sc.noisePower) ~= numBands || ...
        any(~isfinite(sc.noisePower))
    sc.noisePower = max(0.35 * bandPower, eps);
end
if ~isfield(sc, 'bandGain') || numel(sc.bandGain) ~= numBands || ...
        any(~isfinite(sc.bandGain))
    sc.bandGain = ones(numBands, 1);
end

frameSeconds = numel(y) / fs;
noiseFastTime = max(0.05, double(getOptionalField(cfg, ...
    'vadNoiseUpdateFastTime', 0.16)));
noiseSlowTime = max(0.5, double(getOptionalField(cfg, ...
    'vadNoiseUpdateSlowTime', 4.5)));
gainAttackTime = max(0.005, double(getOptionalField(cfg, ...
    'gainAttackTime', 0.035)));
gainReleaseTime = max(0.01, double(getOptionalField(cfg, ...
    'gainReleaseTime', 0.20)));
strength = min(max(double(getOptionalField(cfg, ...
    'noiseReductionStrength', 0.78)), 0), 1);
overSubtraction = min(max(double(getOptionalField(cfg, ...
    'noiseOverSubtraction', 1.10)), 0.8), 2.0);
baseFloor = min(max(double(getOptionalField(cfg, ...
    'noiseFloorGain', 0.24)), 0.05), 1);

alphaFast = exp(-frameSeconds / noiseFastTime);
alphaSlow = exp(-frameSeconds / noiseSlowTime);
alphaAttack = exp(-frameSeconds / gainAttackTime);
alphaRelease = exp(-frameSeconds / gainReleaseTime);

% Floors protect F0/body bands and become gradually lower at high bands.
relativeFloors = [0.52; 0.48; 0.40; 0.32; 0.28; 0.24; 0.22; 0.24];
relativeFloors = max(relativeFloors, baseFloor);

for k = 1:numBands
    % During non-speech, noise tracking is quick. During speech, tracking is
    % intentionally slow so voiced/harmonic energy is not learned as noise.
    alphaNoise = speechProb * alphaSlow + (1-speechProb) * alphaFast;
    candidate = bandPower(k);
    % Limit sudden upward noise estimates during speech transitions.
    if speechProb > 0.55
        candidate = min(candidate, 1.6 * sc.noisePower(k));
    end
    sc.noisePower(k) = alphaNoise * sc.noisePower(k) + ...
        (1-alphaNoise) * candidate;
    sc.noisePower(k) = max(sc.noisePower(k), eps);

    cleanPower = max(bandPower(k) - overSubtraction*sc.noisePower(k), 0);
    wienerGain = sqrt(cleanPower / bandPower(k));
    desiredGain = 1 - strength * (1-wienerGain);

    % In clear non-speech regions, allow somewhat stronger attenuation while
    % preserving a floor to avoid hard gating and musical noise.
    speechScale = 0.72 + 0.28*speechProb;
    desiredGain = desiredGain * speechScale;
    desiredGain = min(max(desiredGain, relativeFloors(k)), 1);

    if desiredGain < sc.bandGain(k)
        alphaGain = alphaAttack;
    else
        alphaGain = alphaRelease;
    end
    sc.bandGain(k) = alphaGain*sc.bandGain(k) + ...
        (1-alphaGain)*desiredGain;
end

y = zeros(size(y));
for k = 1:numBands
    y = y + sc.bandGain(k) * bands{k};
end

% 5) Limited, slowly smoothed compensation only.
inputRms = sqrt(mean(x.^2));
outputRms = sqrt(mean(y.^2));
if inputRms > 1e-7 && outputRms > 1e-7
    desiredGain = clampScalar(inputRms/outputRms, ...
        10^(-1.5/20), 10^(1.5/20));
    if ~isfield(sc, 'makeupGain') || ~isfinite(sc.makeupGain)
        sc.makeupGain = 1;
    end
    sc.makeupGain = 0.94*sc.makeupGain + 0.06*desiredGain;
    y = y * sc.makeupGain;
end

sc.lastSpeechProbability = speechProb;
sc.lastBandGain = sc.bandGain;
state.filter.speechClean = sc;
state.filter.vadSpeechProbability = speechProb;
state.filter.zi = getStructField(sc, 'hpZi', []);
end

function [probability, sc] = estimateSpeechProbability(x, fs, cfg, sc)
frameRms = sqrt(mean(x.^2));
frameDb = 20*log10(frameRms + eps);

if ~isfield(sc, 'vadNoiseFloorDb') || ~isfinite(sc.vadNoiseFloorDb)
    sc.vadNoiseFloorDb = min(frameDb - 6, ...
        double(getOptionalField(cfg, 'vadInitialNoiseFloorDb', -52)));
end
relativeDb = frameDb - sc.vadNoiseFloorDb;
energyScore = logistic((relativeDb - 3.0) / 2.5);

N = numel(x);
if N >= 8
    window = 0.5 - 0.5*cos(2*pi*(0:N-1).' / max(N-1, 1));
    nfft = 2^nextpow2(max(N, 256));
    spectrum = fft(x .* window, nfft);
    powerSpec = abs(spectrum(1:floor(nfft/2)+1)).^2 + eps;
    flatness = exp(mean(log(powerSpec))) / mean(powerSpec);
else
    flatness = 1;
end
flatnessScore = clampScalar((0.70-flatness)/0.55, 0, 1);

if N >= 2
    zcr = mean(abs(diff(x >= 0)));
else
    zcr = 0;
end
if zcr >= 0.015 && zcr <= 0.30
    zcrScore = 1;
else
    zcrScore = clampScalar(1 - abs(zcr-0.12)/0.20, 0, 1);
end

rawProb = 0.64*energyScore + 0.26*flatnessScore + 0.10*zcrScore;
rawProb = clampScalar(rawProb, 0, 1);
if ~isfield(sc, 'vadProbability') || ~isfinite(sc.vadProbability)
    sc.vadProbability = rawProb;
end
frameSeconds = numel(x)/fs;
if rawProb > sc.vadProbability
    tau = max(0.02, double(getOptionalField(cfg, 'vadAttackTime', 0.05)));
else
    tau = max(0.05, double(getOptionalField(cfg, 'vadReleaseTime', 0.30)));
end
alpha = exp(-frameSeconds/tau);
sc.vadProbability = alpha*sc.vadProbability + (1-alpha)*rawProb;
probability = clampScalar(sc.vadProbability, 0, 1);

% Noise-floor tracking: quick during likely non-speech, very slow in speech.
if probability < 0.30
    tauFloor = 0.8;
else
    tauFloor = 8.0;
end
alphaFloor = exp(-frameSeconds/tauFloor);
if frameDb < sc.vadNoiseFloorDb + 12 || probability < 0.35
    sc.vadNoiseFloorDb = alphaFloor*sc.vadNoiseFloorDb + ...
        (1-alphaFloor)*frameDb;
end
sc.vadNoiseFloorDb = min(max(sc.vadNoiseFloorDb, -100), 10);
end

function cutoffs = makeSpeechCleanCutoffs(fs)
base = [180, 350, 700, 1200, 2000, 3200, 4800];
limit = 0.42*fs;
cutoffs = min(base, limit);
for k = 2:numel(cutoffs)
    if cutoffs(k) <= cutoffs(k-1)
        cutoffs(k) = min(limit, cutoffs(k-1) + max(20, 0.01*fs));
    end
end
end

function y = logistic(x)
if x >= 0
    y = 1 / (1 + exp(-x));
else
    ex = exp(x);
    y = ex / (1 + ex);
end
end

function value = clampScalar(value, low, high)
value = min(max(double(value), low), high);
end

function [y, ziOut] = runIirWithState(x, b, a, ziIn)
ziLength = max(numel(a), numel(b)) - 1;
if ziLength <= 0
    y = filter(b, a, x);
    ziOut = [];
    return;
end
if isempty(ziIn) || numel(ziIn) ~= ziLength || any(~isfinite(ziIn))
    ziIn = zeros(ziLength, 1);
else
    ziIn = ziIn(:);
end
[y, ziOut] = filter(b, a, x, ziIn);
end

function [y, prev] = onePoleLowpassState(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2 * pi * cutoff / fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1 - alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end

function value = getStructField(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end
