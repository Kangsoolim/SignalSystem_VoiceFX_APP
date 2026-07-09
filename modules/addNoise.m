function [yFrame, state] = addNoise(xFrame, fs, noiseConfig, state)
%ADDNOISE Add reproducible, stateful noise scenarios for speech experiments.
%   Supported types:
%       none
%       white
%       pink
%       hum50 / hum60 / powerline_hum
%       impulse / impulse_keyboard
%       babble / babble_crowd
%
%   All generated scenarios are frame-safe and preserve state across calls.
%   When noiseConfig.snrDb is finite, the generated noise is scaled toward
%   the requested SNR using a smoothed reference RMS so frame boundaries do
%   not cause abrupt level pumping.

if nargin < 3 || isempty(noiseConfig)
    noiseConfig = struct('enabled', false, 'type', 'none', ...
        'mode', 'none', 'params', struct());
end
if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'noise') || isempty(state.noise)
    state.noise = struct();
end

x = double(xFrame(:));
x(~isfinite(x)) = 0;
yFrame = x;

if ~isfield(noiseConfig, 'enabled') || ~noiseConfig.enabled || isempty(x)
    return;
end
if isempty(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('addNoise:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

noiseType = lower(strtrim(getNoiseType(noiseConfig)));
if strcmp(noiseType, 'none')
    return;
end

setDeterministicFrameSeed(noiseConfig, state);

switch noiseType
    case 'white'
        noise = randn(size(x));

    case 'pink'
        [noise, state] = makePinkNoise(numel(x), fs, state);

    case {'hum50', 'hum60', 'powerline_hum'}
        baseFreq = getField(noiseConfig, 'mainsFreq', 50);
        if strcmp(noiseType, 'hum60')
            baseFreq = 60;
        elseif strcmp(noiseType, 'hum50')
            baseFreq = 50;
        end
        [noise, state] = makePowerlineHum(numel(x), fs, ...
            noiseConfig, state, baseFreq);

    case {'impulse', 'impulse_keyboard'}
        [noise, state] = makeImpulseKeyboard(numel(x), fs, ...
            noiseConfig, state);

    case {'babble', 'babble_crowd'}
        [noise, state] = makeBabbleLikeNoise(numel(x), fs, ...
            noiseConfig, state);

    otherwise
        error('addNoise:UnsupportedNoiseType', ...
            'Unsupported noise type: %s', noiseType);
end

[noise, state] = scaleNoiseLevel(noise, x, fs, noiseConfig, state, noiseType);
yFrame = x + noise;
yFrame(~isfinite(yFrame)) = 0;

noiseRms = sqrt(mean(noise .^ 2));
signalRms = sqrt(mean(x .^ 2));
if noiseRms > eps && signalRms > eps
    state.noise.lastMeasuredSnrDb = 20 * log10(signalRms / noiseRms);
else
    state.noise.lastMeasuredSnrDb = NaN;
end
state.noise.lastType = noiseType;
end

function noiseType = getNoiseType(noiseConfig)
if isfield(noiseConfig, 'type') && ~isempty(noiseConfig.type)
    noiseType = char(noiseConfig.type);
elseif isfield(noiseConfig, 'mode') && ~isempty(noiseConfig.mode)
    noiseType = char(noiseConfig.mode);
else
    noiseType = 'none';
end
end

function setDeterministicFrameSeed(noiseConfig, state)
if ~isfield(noiseConfig, 'seed') || isempty(noiseConfig.seed)
    return;
end
frameOffset = 0;
if isfield(state, 'realtime') && isfield(state.realtime, 'frameIndex') && ...
        ~isempty(state.realtime.frameIndex)
    frameOffset = double(state.realtime.frameIndex);
end
seedValue = round(abs(double(noiseConfig.seed) + frameOffset));
seedValue = mod(seedValue, 2^32 - 1);
rng(seedValue, 'twister');
end

function [noise, state] = makePinkNoise(numSamples, fs, state)
% A stable low-complexity pink-like generator built from two low-pass
% memories plus a small white component. It is intentionally stateful.
if ~isfield(state.noise, 'pinkPrev') || numel(state.noise.pinkPrev) ~= 2
    state.noise.pinkPrev = zeros(2, 1);
end
w = randn(numSamples, 1);
[slow, state.noise.pinkPrev(1)] = onePoleLowpassState( ...
    w, fs, 55, state.noise.pinkPrev(1));
[mid, state.noise.pinkPrev(2)] = onePoleLowpassState( ...
    w, fs, 520, state.noise.pinkPrev(2));
noise = 0.72 * slow + 0.50 * mid + 0.16 * w;
noise = removeMean(noise);
end

function [noise, state] = makePowerlineHum(numSamples, fs, cfg, state, baseFreq)
if ~isfield(state.noise, 'humPhase') || isempty(state.noise.humPhase)
    state.noise.humPhase = 0;
end
numHarmonics = round(getField(cfg, 'humNumHarmonics', 4));
numHarmonics = max(1, min(numHarmonics, 8));
harmonicDecay = getField(cfg, 'humHarmonicDecay', 0.55);
harmonicDecay = min(max(double(harmonicDecay), 0.15), 0.95);

n = (0:numSamples-1).';
phase0 = state.noise.humPhase;
noise = zeros(numSamples, 1);
weightSum = 0;
for h = 1:numHarmonics
    f = h * double(baseFreq);
    if f >= 0.45 * fs
        break;
    end
    weight = harmonicDecay ^ (h - 1);
    noise = noise + weight * sin(phase0 * h + 2*pi*f*n/fs + 0.11*h);
    weightSum = weightSum + weight;
end
if weightSum > 0
    noise = noise / weightSum;
end
state.noise.humPhase = mod(phase0 + 2*pi*double(baseFreq)*numSamples/fs, 2*pi);
end

function [noise, state] = makeImpulseKeyboard(numSamples, fs, cfg, state)
probability = getField(cfg, 'impulseProbability', 0.0015);
probability = min(max(double(probability), 0), 0.20);
clickWidthMs = getField(cfg, 'impulseClickWidthMs', 3.0);
clickWidthMs = min(max(double(clickWidthMs), 0.5), 20);

impulses = zeros(numSamples, 1);
mask = rand(numSamples, 1) < probability;
impulses(mask) = 2 * (rand(sum(mask), 1) > 0.5) - 1;

% A short decaying resonant click is closer to keyboard/transient noise than
% a single isolated sample. The IIR tail is carried between frames.
decayTime = max(clickWidthMs * 1e-3, 1 / fs);
r = exp(-1 / max(decayTime * fs, 1));
resonanceHz = min(getField(cfg, 'impulseResonanceHz', 1800), 0.40 * fs);
theta = 2*pi*resonanceHz/fs;
a = [1, -2*r*cos(theta), r^2];
b = [1-r, 0, -(1-r)];
ziLength = max(numel(a), numel(b)) - 1;
if ~isfield(state.noise, 'impulseZi') || ...
        numel(state.noise.impulseZi) ~= ziLength
    state.noise.impulseZi = zeros(ziLength, 1);
end
[noise, state.noise.impulseZi] = filter( ...
    b, a, impulses, state.noise.impulseZi);
end

function [noise, state] = makeBabbleLikeNoise(numSamples, fs, cfg, state)
% Multi-source speech-shaped crowd approximation. This is synthetic
% babble-like interference, not a replacement for a recorded crowd corpus.
numVoices = round(getField(cfg, 'babbleVoices', 6));
numVoices = max(3, min(numVoices, 10));

if ~isfield(state.noise, 'babbleLpPrev') || ...
        ~isequal(size(state.noise.babbleLpPrev), [numVoices, 2])
    state.noise.babbleLpPrev = zeros(numVoices, 2);
end
if ~isfield(state.noise, 'babblePhase') || ...
        numel(state.noise.babblePhase) ~= numVoices
    state.noise.babblePhase = linspace(0, pi, numVoices).';
end

noise = zeros(numSamples, 1);
n = (0:numSamples-1).';
for k = 1:numVoices
    w = randn(numSamples, 1);
    lowCut = 140 + 35 * mod(k-1, 3);
    highCut = min(2900 + 260 * mod(k-1, 4), 0.42 * fs);
    [lpHigh, state.noise.babbleLpPrev(k, 2)] = onePoleLowpassState( ...
        w, fs, highCut, state.noise.babbleLpPrev(k, 2));
    [lpLow, state.noise.babbleLpPrev(k, 1)] = onePoleLowpassState( ...
        lpHigh, fs, lowCut, state.noise.babbleLpPrev(k, 1));
    speechBand = lpHigh - lpLow;

    rateHz = 1.4 + 0.37 * k;
    phase = state.noise.babblePhase(k) + 2*pi*rateHz*n/fs;
    modulator = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase)) .^ 1.7;
    noise = noise + modulator .* speechBand;
    state.noise.babblePhase(k) = mod( ...
        state.noise.babblePhase(k) + 2*pi*rateHz*numSamples/fs, 2*pi);
end
noise = removeMean(noise / sqrt(numVoices));
end

function [noise, state] = scaleNoiseLevel(noise, x, fs, cfg, state, noiseType)
noise = double(noise(:));
noise(~isfinite(noise)) = 0;
noiseRms = sqrt(mean(noise .^ 2));
if noiseRms <= eps
    noise = zeros(size(noise));
    return;
end

signalRms = sqrt(mean(x .^ 2));
if ~isfield(state.noise, 'referenceRms') || ...
        ~isfinite(state.noise.referenceRms) || state.noise.referenceRms <= 0
    state.noise.referenceRms = max(signalRms, 1e-4);
end

frameSeconds = numel(x) / fs;
if signalRms > state.noise.referenceRms
    tau = max(getField(cfg, 'snrReferenceAttackTime', 0.12), 0.01);
else
    tau = max(getField(cfg, 'snrReferenceReleaseTime', 1.20), 0.05);
end
alpha = exp(-frameSeconds / tau);
if signalRms > 1e-7
    state.noise.referenceRms = alpha * state.noise.referenceRms + ...
        (1-alpha) * signalRms;
end

% Preserve the original project's fixed white-noise mode for backward
% compatibility. All other scenarios, and white noise in SNR mode, use the
% smoothed SNR reference.
whiteMode = lower(char(getField(cfg, 'whiteMode', 'fixed')));
useFixedWhite = strcmp(noiseType, 'white') && strcmp(whiteMode, 'fixed');
snrDb = getField(cfg, 'snrDb', []);
if useFixedWhite
    targetNoiseRms = abs(double(getField(cfg, 'noiseLevel', 0.02)));
elseif ~isempty(snrDb) && isscalar(snrDb) && isfinite(double(snrDb))
    targetNoiseRms = state.noise.referenceRms / (10^(double(snrDb)/20));
else
    targetNoiseRms = abs(double(getField(cfg, 'noiseLevel', 0.02)));
end
minimumRms = abs(double(getField(cfg, 'minimumNoiseRms', 0)));
targetNoiseRms = max(targetNoiseRms, minimumRms);
noise = noise / noiseRms * targetNoiseRms;
end

function [y, prev] = onePoleLowpassState(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2*pi*cutoff/fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1-alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end

function y = removeMean(x)
y = x - mean(x);
end

function value = getField(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
