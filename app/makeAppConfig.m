function config = makeAppConfig(varargin)
%MAKEAPPCONFIG Build a VoiceFX backend config from App selections.
%   CONFIG = MAKEAPPCONFIG(SELECTIONS) accepts a struct with fields such as
%   noise, filter, voice, fx, space, and am. Name-value pairs are supported
%   as well. The function starts from makeDefaultConfig so backend defaults
%   remain the single source of truth.

config = makeDefaultConfig();
selections = normalizeSelections(varargin{:});

config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.90;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
config.output.limiterMode = 'soft';

noiseMode = mapMode(getSelection(selections, {'noise', 'noiseMode'}, 'none'), 'noise');
config.noise.enabled = ~strcmp(noiseMode, 'none');
config.noise.type = noiseMode;
config.noise.mode = noiseMode;
if strcmp(noiseMode, 'white')
    config.noise.whiteMode = 'smooth_snr';
    config.noise.snrDb = 24;
elseif strcmp(noiseMode, 'impulse')
    config.noise.noiseLevel = 0.08;
    config.noise.impulseProbability = 0.0008;
end

filterMode = mapMode(getSelection(selections, {'filter', 'filterMode'}, 'none'), 'filter');
config.filter.enabled = ~strcmp(filterMode, 'none');
config.filter.type = filterMode;
config.filter.mode = filterMode;

voiceMode = mapMode(getSelection(selections, {'voice', 'voiceMode'}, 'none'), 'voice');
config.voice.enabled = ~strcmp(voiceMode, 'none');
config.voice.type = voiceMode;
config.voice.mode = voiceMode;
if strcmp(voiceMode, 'robot_voice')
    config.voice.modFreq = 42;
    config.voice.intensity = 0.70;
end

fxMode = mapMode(getSelection(selections, {'fx', 'effect', 'fxMode'}, 'none'), 'fx');
config.fx.enabled = ~strcmp(fxMode, 'none');
config.fx.type = fxMode;
config.fx.mode = fxMode;

spaceMode = mapMode(getSelection(selections, {'space', 'spaceMode'}, 'none'), 'space');
config.space.enabled = ~strcmp(spaceMode, 'none');
config.space.type = spaceMode;
config.space.mode = spaceMode;

amMode = mapMode(getSelection(selections, {'am', 'amMode', 'modDemod'}, 'off'), 'am');
config.modDemod.enabled = ~strcmp(amMode, 'none');
config.modDemod.type = amMode;
config.modDemod.mode = amMode;
config.modDemod.showInApp = true;
config.modDemod.processingTarget = 'app_file_mode';
config.modDemod.useZeroPhase = false;
end

function selections = normalizeSelections(varargin)
selections = struct();
if isempty(varargin)
    return;
end
if numel(varargin) == 1 && isstruct(varargin{1})
    selections = varargin{1};
    return;
end
if mod(numel(varargin), 2) ~= 0
    error('makeAppConfig:InvalidInput', 'Use a selections struct or name-value pairs.');
end
for k = 1:2:numel(varargin)
    selections.(char(varargin{k})) = varargin{k + 1};
end
end

function value = getSelection(selections, names, defaultValue)
value = defaultValue;
for k = 1:numel(names)
    name = names{k};
    if isfield(selections, name) && ~isempty(selections.(name))
        value = selections.(name);
        return;
    end
end
end

function mode = mapMode(value, groupName)
mode = lower(strtrim(char(value)));
mode = strrep(mode, '-', '_');
mode = strrep(mode, ' ', '_');

switch groupName
    case 'voice'
        switch mode
            case {'elderly', 'old', 'elder'}
                mode = 'elder';
            case {'robot', 'robotvoice'}
                mode = 'robot_voice';
        end

    case 'fx'
        switch mode
            case {'walkie', 'walkie-talkie', 'walkie_talkie'}
                mode = 'walkie_talkie';
            case {'gramophone_classic', 'vinyl', 'old_record'}
                mode = 'gramophone';
        end

    case 'space'
        switch mode
            case {'reverb', 'small_room'}
                mode = 'bathroom';
            case {'stage'}
                mode = 'bathroom';
        end

    case 'am'
        switch mode
            case {'off', 'none', 'disable', 'disabled'}
                mode = 'none';
            case {'modulate', 'am_modulate'}
                mode = 'am_modulate';
            case {'demodulate', 'am_demodulate'}
                mode = 'am_demodulate';
        end
end

mode = validateMode(mode, groupName);
end

function mode = validateMode(mode, groupName)
switch groupName
    case 'noise'
        allowed = {'none', 'white', 'hum50', 'impulse'};
    case 'filter'
        allowed = {'none', 'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};
    case 'voice'
        allowed = {'none', 'male', 'female', 'child', 'elder', 'anonymous', 'robot_voice'};
    case 'fx'
        allowed = {'none', 'telephone', 'walkie_talkie', 'radio', 'lofi', 'bitcrusher', 'gramophone', 'robot'};
    case 'space'
        allowed = {'none', 'delay', 'bathroom', 'cave'};
    case 'am'
        allowed = {'none', 'am_modulate', 'am_demodulate'};
    otherwise
        allowed = {'none'};
end

if ~ismember(mode, allowed)
    warning('makeAppConfig:UnsupportedMode', 'Unsupported %s mode "%s"; using none.', groupName, mode);
    mode = 'none';
end
end
