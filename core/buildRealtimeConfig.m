function config = buildRealtimeConfig(voiceMode, options, baseConfig)
%BUILDREALTIMECONFIG Build one validated config for CLI and Dashboard realtime use.
%   CONFIG = BUILDREALTIMECONFIG(VOICEMODE, OPTIONS) translates UI/CLI
%   controls into the existing VoiceFX processing-chain configuration.
%
%   The function deliberately keeps audio I/O settings separate from DSP
%   state. Sample rate and frame length are read by the realtime I/O runner,
%   while this config controls the modules called by processAudioFrame.

if nargin < 1 || isempty(voiceMode)
    voiceMode = 'female';
end
if nargin < 2 || isempty(options)
    options = struct();
end
if nargin < 3 || isempty(baseConfig)
    config = makeDefaultConfig();
else
    config = fillTopLevelDefaults(baseConfig, makeDefaultConfig());
end

frameLength = round(readOption(options, 'frameLength', config.audio.frameLength));
if ~isscalar(frameLength) || ~isfinite(frameLength) || frameLength < 32
    error('buildRealtimeConfig:InvalidFrameLength', ...
        'frameLength must be a finite scalar of at least 32 samples.');
end
config.audio.frameLength = frameLength;
config.audio.normalizeInput = false;
config.audio.removeDC = false;

inputGainDb = readOption(options, 'inputGainDb', config.audio.inputGainDb);
config.audio.inputGainDb = clampFinite(inputGainDb, -24, 24, 0);

% Speech enhancement
config.filter.enabled = logicalScalar(readOption(options, ...
    'enableSpeechClean', true), true);
if config.filter.enabled
    config.filter.type = 'speech_clean';
    config.filter.mode = 'speech_clean';
else
    config.filter.type = 'none';
    config.filter.mode = 'none';
end

% Voice style
voiceMode = canonicalText(voiceMode, 'female');
config.voice.enabled = logicalScalar(readOption(options, 'enableVoice', true), true) ...
    && ~strcmpi(voiceMode, 'none');
config.voice.type = voiceMode;
config.voice.mode = voiceMode;
config.voice.mix = clampFinite(readOption(options, 'voiceMix', 1.0), 0, 1, 1.0);
config.voice.intensity = clampFinite(readOption(options, 'intensity', 0.62), 0, 1, 0.62);
config.voice.params.adaptiveEnabled = logicalScalar(readOption(options, ...
    'adaptiveVoice', true), true);
config.voice.params.calibrationSeconds = clampFinite(readOption(options, ...
    'calibrationSeconds', 0.80), 0.25, 5.0, 0.80);

% Vocal/device FX
fxMode = canonicalText(readOption(options, 'fxMode', 'none'), 'none');
config.fx.enabled = logicalScalar(readOption(options, 'enableFx', ...
    ~strcmpi(fxMode, 'none')), ~strcmpi(fxMode, 'none')) ...
    && ~strcmpi(fxMode, 'none');
config.fx.type = fxMode;
config.fx.mode = fxMode;
config.fx.mix = clampFinite(readOption(options, 'fxMix', 1.0), 0, 1, 1.0);
config.fx.intensity = clampFinite(readOption(options, 'fxIntensity', 0.60), 0, 1, 0.60);

% Space FX
spaceMode = canonicalText(readOption(options, 'spaceMode', 'none'), 'none');
config.space.enabled = logicalScalar(readOption(options, 'enableSpace', ...
    ~strcmpi(spaceMode, 'none')), ~strcmpi(spaceMode, 'none')) ...
    && ~strcmpi(spaceMode, 'none');
config.space.type = spaceMode;
config.space.mode = spaceMode;
config.space.mix = clampFinite(readOption(options, 'spaceMix', config.space.mix), ...
    0, 1, config.space.mix);

% AM stays opt-in for realtime. The Dashboard exposes AM as an analysis lab,
% while this switch exists for controlled experiments and regression tests.
enableAM = logicalScalar(readOption(options, 'enableAM', false), false);
amMode = canonicalText(readOption(options, 'amMode', 'none'), 'none');
config.modDemod.enabled = enableAM && ~strcmpi(amMode, 'none');
config.modDemod.type = amMode;
config.modDemod.mode = amMode;
config.modDemod.normalizeOutput = false;
if isfield(options, 'carrierFreq') && ~isempty(options.carrierFreq)
    config.modDemod.carrierFreq = double(options.carrierFreq);
end
if isfield(options, 'modulationIndex') && ~isempty(options.modulationIndex)
    config.modDemod.modulationIndex = double(options.modulationIndex);
end

config.output.limitEnabled = true;
config.output.limiterMode = canonicalText(readOption(options, ...
    'limiterMode', 'soft'), 'soft');
end

function value = readOption(options, name, defaultValue)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end

function value = clampFinite(value, low, high, fallback)
value = double(value);
if ~isscalar(value) || ~isfinite(value)
    value = fallback;
end
value = min(max(value, low), high);
end

function text = canonicalText(value, fallback)
try
    text = strtrim(char(value));
catch
    text = fallback;
end
if isempty(text)
    text = fallback;
end
end

function tf = logicalScalar(value, fallback)
if islogical(value) || isnumeric(value)
    if isempty(value)
        tf = fallback;
    else
        tf = logical(value(1));
    end
    return;
end
try
    text = lower(strtrim(char(value)));
    tf = any(strcmp(text, {'true','on','yes','1'}));
catch
    tf = fallback;
end
end

function value = fillTopLevelDefaults(value, defaults)
if ~isstruct(value)
    value = defaults;
    return;
end
fields = fieldnames(defaults);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(value, name) || isempty(value.(name))
        value.(name) = defaults.(name);
    elseif isstruct(value.(name)) && isstruct(defaults.(name))
        value.(name) = fillTopLevelDefaults(value.(name), defaults.(name));
    end
end
end
