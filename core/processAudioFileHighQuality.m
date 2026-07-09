function [y, state, diagnostics] = processAudioFileHighQuality(x, fs, config)
%PROCESSAUDIOFILEHIGHQUALITY Offline-quality full-file processing chain.
%   The chain keeps the same stage order as processAudioFrame, but performs
%   voice transformation on the complete utterance using processVoiceFileHQ.
%
%   This function is for loaded files/export. Realtime microphone processing
%   must continue to call processAudioFrame so every stateful module advances
%   causally frame by frame.

if nargin < 3 || isempty(config)
    config = makeDefaultConfig();
end
config = fillConfig(config);
state = initProcessState(config);

x = preprocessAudio(x, fs, config);
if isempty(x)
    y = zeros(0,1);
    diagnostics = struct('status','empty');
    return;
end

frameLength = max(1, round(config.audio.frameLength));
frameConfig = config;
frameConfig.audio.removeDC = false;
frameConfig.audio.normalizeInput = false;

% Stage A: source/noise/filter, frame-continuous.
stageA = zeros(size(x));
for startIndex = 1:frameLength:numel(x)
    stopIndex = min(startIndex+frameLength-1, numel(x));
    frame = x(startIndex:stopIndex);
    [frame, state] = addNoise(frame, fs, frameConfig.noise, state);
    [frame, state] = applyDenoiseFilter(frame, fs, frameConfig.filter, state);
    stageA(startIndex:stopIndex) = forceLength(frame, stopIndex-startIndex+1);
end

% Stage B: high-quality full-utterance voice conversion.
[stageB, voiceDiagnostics] = processVoiceFileHQ(stageA, fs, config.voice);

% Stage C: FX/space/mod-demod remain frame-continuous.
y = zeros(size(stageB));
for startIndex = 1:frameLength:numel(stageB)
    stopIndex = min(startIndex+frameLength-1, numel(stageB));
    frame = stageB(startIndex:stopIndex);
    [frame, state] = applyVocalFX(frame, fs, frameConfig.fx, state);
    [frame, state] = applySpaceFX(frame, fs, frameConfig.space, state);
    [~, frame, state] = applyModDemod(frame, fs, frameConfig.modDemod, state);
    frame = safeLimiter(frame, config);
    y(startIndex:stopIndex) = forceLength(frame, stopIndex-startIndex+1);
end

y = safeLimiter(y, config);
diagnostics = struct();
diagnostics.status = 'ok';
diagnostics.voice = voiceDiagnostics;
diagnostics.frameLength = frameLength;
end

function y = forceLength(y, n)
y = double(y(:));
y(~isfinite(y)) = 0;
if numel(y) < n
    y(end+1:n,1) = 0;
elseif numel(y) > n
    y = y(1:n);
end
end

function config = fillConfig(config)
defaults = makeDefaultConfig();
fields = fieldnames(defaults);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config,name) || isempty(config.(name))
        config.(name) = defaults.(name);
    elseif isstruct(config.(name)) && isstruct(defaults.(name))
        sub = fieldnames(defaults.(name));
        for j = 1:numel(sub)
            subName = sub{j};
            if ~isfield(config.(name),subName)
                config.(name).(subName) = defaults.(name).(subName);
            end
        end
    end
end
end
