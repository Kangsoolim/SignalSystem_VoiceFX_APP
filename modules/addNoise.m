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
        yFrame = yFrame + makeWhiteNoise(yFrame, noiseConfig);
    case 'hum50'
        yFrame = yFrame + makeHumNoise(numel(yFrame), fs, noiseConfig);
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

function noise = makeWhiteNoise(x, noiseConfig)
noise = randn(size(x));

if isfield(noiseConfig, 'snrDb') && ~isempty(noiseConfig.snrDb)
    signalRms = sqrt(mean(x.^2));
    if signalRms > eps
        noiseRms = signalRms / (10^(double(noiseConfig.snrDb) / 20));
    else
        noiseRms = getNoiseLevel(noiseConfig);
    end
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

function noise = makeHumNoise(numSamples, fs, noiseConfig)
if isempty(fs) || fs <= 0 || numSamples == 0
    noise = zeros(numSamples, 1);
    return;
end

humAmplitude = getFieldOrDefault(noiseConfig, 'humAmplitude', 0.02);
t = (0:numSamples-1).' / fs;
noise = double(humAmplitude) * sin(2 * pi * 50 * t);
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
