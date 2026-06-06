function [y, state] = processAudioFile(x, fs, config)
%PROCESSAUDIOFILE Process a full audio vector through the frame pipeline.
%   File mode is intentionally implemented by calling processAudioFrame so
%   later realtime and file behavior share the same module chain.

if nargin < 3 || isempty(config)
    config = makeDefaultConfig();
end
config = fillFrameworkConfig(config);

state = initProcessState(config);
x = preprocessAudio(x, fs, config);
frameConfig = config;
frameConfig.audio.removeDC = false;
frameConfig.audio.normalizeInput = false;

frameLength = config.audio.frameLength;
if isempty(frameLength) || frameLength <= 0
    frameLength = numel(x);
end
frameLength = max(1, round(frameLength));

y = zeros(size(x), 'like', x);

if isempty(x)
    y = zeros(0, 1);
    return;
end

for startIndex = 1:frameLength:numel(x)
    stopIndex = min(startIndex + frameLength - 1, numel(x));
    frame = x(startIndex:stopIndex);
    expectedLength = numel(frame);

    [yFrame, state] = processAudioFrame(frame, fs, frameConfig, state);
    yFrame = yFrame(:);

    if numel(yFrame) < expectedLength
        yFrame(end + 1:expectedLength, 1) = 0;
    elseif numel(yFrame) > expectedLength
        yFrame = yFrame(1:expectedLength);
    end

    y(startIndex:stopIndex) = yFrame;
end

y = safeLimiter(y, config);
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
