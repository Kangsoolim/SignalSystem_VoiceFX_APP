function [yFrame, state] = processAudioFrame(xFrame, fs, config, state)
%PROCESSAUDIOFRAME Shared frame pipeline for file and realtime modes.
%   Current stage only wires module interfaces together. Enabled modules
%   still pass audio through until their concrete algorithms are added.

if nargin < 3 || isempty(config)
    config = makeDefaultConfig();
end
config = fillFrameworkConfig(config);

if nargin < 4 || isempty(state)
    state = initProcessState(config);
end

if isvector(xFrame)
    inputLength = numel(xFrame);
else
    inputLength = size(xFrame, 1);
end

yFrame = preprocessAudio(xFrame, fs, config);

[yFrame, state] = addNoise(yFrame, fs, config.noise, state);
[yFrame, state] = applyDenoiseFilter(yFrame, fs, config.filter, state);
[yFrame, state] = applyVoiceStyle(yFrame, fs, config.voice, state);
[yFrame, state] = applyVocalFX(yFrame, fs, config.fx, state);
[yFrame, state] = applySpaceFX(yFrame, fs, config.space, state);
[~, yFrame, state] = applyModDemod(yFrame, fs, config.modDemod, state);

yFrame = safeLimiter(yFrame, config);
yFrame = yFrame(:);

if numel(yFrame) < inputLength
    yFrame(end + 1:inputLength, 1) = 0;
elseif numel(yFrame) > inputLength
    yFrame = yFrame(1:inputLength);
end

yFrame = safeLimiter(yFrame, config);

state.realtime.frameIndex = state.realtime.frameIndex + 1;
state.debug.lastFs = fs;
state.debug.lastFrameLength = numel(yFrame);
end

function config = fillFrameworkConfig(config)
defaults = makeDefaultConfig();
requiredFields = {'audio', 'noise', 'filter', 'voice', 'fx', 'space', 'modDemod', 'output', 'display'};
for k = 1:numel(requiredFields)
    name = requiredFields{k};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    else
        config.(name) = fillStructDefaults(config.(name), defaults.(name));
    end
end
end

function value = fillStructDefaults(value, defaults)
defaultFields = fieldnames(defaults);
for k = 1:numel(defaultFields)
    name = defaultFields{k};
    if ~isfield(value, name)
        value.(name) = defaults.(name);
    end
end
end
