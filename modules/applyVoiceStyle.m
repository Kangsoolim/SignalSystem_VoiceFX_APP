function [yFrame, state] = applyVoiceStyle(xFrame, fs, voiceConfig, state)
%APPLYVOICESTYLE Compatibility wrapper for legacy and adaptive voice engines.
%   Old App modes use the legacy path by default. New deep voice modes, or
%   explicit params.adaptiveEnabled/engine='adaptive', use the adaptive path.

if nargin < 3 || isempty(voiceConfig)
    voiceConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
if nargin < 4 || isempty(state)
    state = initProcessState();
end

voiceMode = getVoiceModeLocal(voiceConfig);
params = getVoiceParamsLocal(voiceConfig);
engine = lower(strtrim(char(getFieldLocal(params, 'engine', ''))));
adaptiveEnabled = logicalScalarLocal(getFieldLocal(params, 'adaptiveEnabled', false));
useAdaptive = isDeepVoiceModeLocal(voiceMode) || adaptiveEnabled || strcmp(engine, 'adaptive');

if ~useAdaptive
    [yFrame, state] = applyVoiceStyleLegacy(xFrame, fs, voiceConfig, state);
    return;
end

adaptiveConfig = voiceConfig;
adaptiveConfig.params = params;
adaptiveConfig.params.adaptiveEnabled = true;
adaptiveConfig.params.engine = 'adaptive';

try
    [yFrame, state] = applyVoiceStyleAdaptive(xFrame, fs, adaptiveConfig, state);
catch adaptiveError
    legacyConfig = voiceConfig;
    legacyConfig.params = params;
    legacyConfig.params.adaptiveEnabled = false;
    legacyConfig.params.engine = 'legacy';
    legacyConfig.mode = mapDeepModeToLegacyLocal(voiceMode);
    legacyConfig.type = legacyConfig.mode;

    try
        [yFrame, state] = applyVoiceStyleLegacy(xFrame, fs, legacyConfig, state);
    catch legacyError
        yFrame = safeOriginalLocal(xFrame);
        if ~isfield(state, 'voice') || isempty(state.voice)
            state.voice = struct();
        end
        state.voice.lastFallback = 'safe_original';
        state.voice.lastAdaptiveError = adaptiveError.message;
        state.voice.lastLegacyError = legacyError.message;
    end
end
end

function mode = getVoiceModeLocal(config)
if isstruct(config) && isfield(config, 'type') && ~isempty(config.type)
    mode = lower(strtrim(char(config.type)));
elseif isstruct(config) && isfield(config, 'mode') && ~isempty(config.mode)
    mode = lower(strtrim(char(config.mode)));
else
    mode = 'none';
end
mode = strrep(mode, '-', '_');
mode = strrep(mode, ' ', '_');
if strcmp(mode, 'elderly')
    mode = 'elder';
elseif strcmp(mode, 'robot')
    mode = 'robot_voice';
end
end

function params = getVoiceParamsLocal(config)
if isstruct(config) && isfield(config, 'params') && isstruct(config.params)
    params = config.params;
else
    params = struct();
end
end

function tf = isDeepVoiceModeLocal(mode)
tf = any(strcmp(mode, {'male_deep_gentle', 'female_gentle_sweet', ...
    'child_bright_soft', 'elder_warm_steady'}));
end

function legacyMode = mapDeepModeToLegacyLocal(mode)
switch mode
    case 'male_deep_gentle'
        legacyMode = 'male';
    case 'female_gentle_sweet'
        legacyMode = 'female';
    case 'child_bright_soft'
        legacyMode = 'child';
    case 'elder_warm_steady'
        legacyMode = 'elder';
    otherwise
        legacyMode = mode;
end
end

function value = getFieldLocal(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function tf = logicalScalarLocal(value)
if islogical(value)
    tf = any(value(:));
elseif isnumeric(value)
    tf = any(value(:) ~= 0);
elseif ischar(value) || isstring(value)
    text = lower(strtrim(char(value)));
    tf = any(strcmp(text, {'true', 'on', 'yes', '1', 'adaptive'}));
else
    tf = false;
end
end

function y = safeOriginalLocal(x)
y = double(x);
y = y(:);
y(~isfinite(y)) = 0;
y = min(max(y, -0.98), 0.98);
end
