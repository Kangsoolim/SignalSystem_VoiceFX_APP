function state = initProcessState(config)
%INITPROCESSSTATE Create the state scaffold shared by file and realtime modes.
%   State fields are intentionally empty placeholders for later frame-based
%   filters, voice effects, delay/reverb buffers, and realtime counters.

if nargin < 1 || isempty(config)
    config = makeDefaultConfig();
end

state = struct();
state.filter = struct();
state.voice = struct();
state.fx = struct();
state.space = struct();
state.realtime = struct();
state.debug = struct();

state.realtime.frameIndex = 0;
state.debug.lastFs = [];
state.debug.lastFrameLength = [];
state.debug.configAudio = config.audio;
end
