function [yFrame, state] = applyStyleDynamics(xFrame, fs, voiceConfig, state)
%APPLYSTYLEDYNAMICS Stateful soft RMS compressor for voice-style control.

x = double(xFrame(:));
x(~isfinite(x)) = 0;
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
if ~isfield(state.voice, 'styleDynamics') || isempty(state.voice.styleDynamics)
    state.voice.styleDynamics = struct('gainDb', 0);
end
dyn = state.voice.styleDynamics;
if ~isfield(dyn, 'gainDb') || ~isfinite(dyn.gainDb)
    dyn.gainDb = 0;
end

thresholdDb = getParam(voiceConfig, 'compressorThresholdDb', -18);
ratio = max(getParam(voiceConfig, 'compressorRatio', 2.0), 1);
makeupDb = getParam(voiceConfig, 'compressorMakeupDb', 0.5);
attack = max(getParam(voiceConfig, 'compressorAttackTime', 0.05), 0.005);
release = max(getParam(voiceConfig, 'compressorReleaseTime', 0.22), 0.02);

levelDb = 20*log10(sqrt(mean(x.^2)) + eps);
if levelDb > thresholdDb
    compressedDb = thresholdDb + (levelDb - thresholdDb) / ratio;
    targetGainDb = compressedDb - levelDb + makeupDb;
else
    targetGainDb = makeupDb;
end
targetGainDb = min(max(targetGainDb, -8), 3);
frameSeconds = numel(x)/fs;
if targetGainDb < dyn.gainDb
    alpha = exp(-frameSeconds/attack);
else
    alpha = exp(-frameSeconds/release);
end
dyn.gainDb = alpha*dyn.gainDb + (1-alpha)*targetGainDb;
yFrame = x * 10^(dyn.gainDb/20);
state.voice.styleDynamics = dyn;
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
