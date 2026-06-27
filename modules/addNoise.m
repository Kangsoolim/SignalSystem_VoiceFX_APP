function [yFrame, state] = addNoise(xFrame, fs, noiseConfig, state)
%ADDNOISE Add simple generated noise for framework-level experiments.
%   Supported types are none, white, hum50, and impulse. This module does
%   not read external noise files or implement complex environment noise.

if nargin < 3 || isempty(noiseConfig)
    noiseConfig = struct('enabled', false, 'type', 'none', 'mode', 'none', 'params', struct());
end

if nargin < 4 || isempty(state)
    state = initProcessState();
end

yFrame = double(xFrame);
yFrame = yFrame(:);
yFrame(~isfinite(yFrame)) = 0;

if ~isfield(noiseConfig, 'enabled') || ~noiseConfig.enabled
    return;
end

noiseType = getNoiseType(noiseConfig);

if isfield(noiseConfig, 'seed') && ~isempty(noiseConfig.seed)
    frameOffset = 0;
    if isfield(state, 'realtime') && isfield(state.realtime, 'frameIndex')
        frameOffset = state.realtime.frameIndex;
    end
    seedValue = round(abs(double(noiseConfig.seed) + double(frameOffset)));
    seedValue = mod(seedValue, 2^32);
    rng(seedValue, 'twister');
end

switch lower(noiseType)
    case 'none'
        return;
    case 'white'
        [whiteNoise, state] = makeWhiteNoise(yFrame, fs, noiseConfig, state);
        yFrame = yFrame + whiteNoise;
    case 'hum50'
        [humNoise, state] = makeHumNoise(numel(yFrame), fs, noiseConfig, state);
        yFrame = yFrame + humNoise;
    case 'impulse'
        yFrame = yFrame + makeImpulseNoise(numel(yFrame), noiseConfig);
    otherwise
        return;
end

yFrame(~isfinite(yFrame)) = 0;
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

function [noise, state] = makeWhiteNoise(x, fs, noiseConfig, state)
noise = randn(size(x));

whiteMode = getFieldOrDefault(noiseConfig, 'whiteMode', 'fixed');
if strcmpi(char(whiteMode), 'smooth_snr')
    noiseRms = getSmoothedSnrNoiseRms(x, fs, noiseConfig, state);
    state = updateWhiteNoiseState(x, fs, noiseConfig, state, noiseRms);
else
    noiseRms = getNoiseLevel(noiseConfig);
end

currentRms = sqrt(mean(noise.^2));
if currentRms > eps
    noise = noise / currentRms * noiseRms;
else
    noise = zeros(size(x));
end
end

function noiseRms = getSmoothedSnrNoiseRms(x, fs, noiseConfig, state)
targetRms = getWhiteSnrTargetRms(x, noiseConfig);
previousRms = [];
if isfield(state, 'noise') && isfield(state.noise, 'whiteRms') && ~isempty(state.noise.whiteRms)
    previousRms = state.noise.whiteRms;
end

if isempty(previousRms) || ~isfinite(previousRms) || previousRms <= 0 || isempty(fs) || fs <= 0
    noiseRms = targetRms;
    return;
end

frameSeconds = numel(x) / fs;
if targetRms > previousRms
    timeConstant = getFieldOrDefault(noiseConfig, 'whiteAttackTime', 0.30);
else
    timeConstant = getFieldOrDefault(noiseConfig, 'whiteReleaseTime', 1.00);
end
timeConstant = max(0.001, abs(double(timeConstant)));
alpha = exp(-frameSeconds / timeConstant);
noiseRms = alpha * previousRms + (1 - alpha) * targetRms;
end

function targetRms = getWhiteSnrTargetRms(x, noiseConfig)
floorRms = getFieldOrDefault(noiseConfig, 'whiteFloorLevel', getNoiseLevel(noiseConfig) * 0.10);
floorRms = abs(double(floorRms));
if isfield(noiseConfig, 'snrDb') && ~isempty(noiseConfig.snrDb)
    signalRms = sqrt(mean(x.^2));
    if signalRms > eps
        targetRms = max(signalRms / (10^(double(noiseConfig.snrDb) / 20)), floorRms);
    else
        targetRms = floorRms;
    end
else
    targetRms = getNoiseLevel(noiseConfig);
end
end

function state = updateWhiteNoiseState(x, fs, noiseConfig, state, noiseRms)
if ~isfield(state, 'noise') || isempty(state.noise)
    state.noise = struct();
end
if strcmpi(char(getFieldOrDefault(noiseConfig, 'whiteMode', 'fixed')), 'smooth_snr') && ...
        ~isempty(fs) && fs > 0 && ~isempty(x)
    state.noise.whiteRms = noiseRms;
end
end

function [noise, state] = makeHumNoise(numSamples, fs, noiseConfig, state)
if isempty(fs) || fs <= 0 || numSamples == 0
    noise = zeros(numSamples, 1);
    return;
end

humAmplitude = getFieldOrDefault(noiseConfig, 'humAmplitude', 0.02);
harmonicRatio = getFieldOrDefault(noiseConfig, 'humHarmonicRatio', 0.25);
harmonicRatio = max(0, min(double(harmonicRatio), 1));

if ~isfield(state, 'noise') || isempty(state.noise)
    state.noise = struct();
end
if ~isfield(state.noise, 'humPhase') || isempty(state.noise.humPhase)
    state.noise.humPhase = 0;
end

phaseStep = 2 * pi * 50 / fs;
phase = state.noise.humPhase + phaseStep * (0:numSamples-1).';
fundamental = sin(phase);
secondHarmonic = sin(2 * phase + pi / 7);
noise = double(humAmplitude) * (fundamental + harmonicRatio * secondHarmonic);
state.noise.humPhase = mod(state.noise.humPhase + phaseStep * numSamples, 2 * pi);
end

function noise = makeImpulseNoise(numSamples, noiseConfig)
probability = getFieldOrDefault(noiseConfig, 'impulseProbability', 0.001);
probability = max(0, min(double(probability), 1));
level = getNoiseLevel(noiseConfig);

mask = rand(numSamples, 1) < probability;
signs = 2 * (rand(numSamples, 1) > 0.5) - 1;
noise = level * mask .* signs;
end

function value = getNoiseLevel(noiseConfig)
value = getFieldOrDefault(noiseConfig, 'noiseLevel', 0.02);
value = abs(double(value));
end

function value = getFieldOrDefault(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end
