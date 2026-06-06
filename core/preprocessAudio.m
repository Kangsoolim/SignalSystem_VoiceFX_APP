function x = preprocessAudio(x, fs, config)
%PREPROCESSAUDIO Normalize framework input shape without applying effects.
%   Audio is converted to a double column vector. Multi-channel input is
%   averaged to mono so later modules receive a consistent interface.

if nargin < 2
    fs = [];
end

if nargin < 3 || isempty(config)
    config = makeDefaultConfig();
end
config = fillAudioDefaults(config);

if isempty(x)
    x = zeros(0, 1);
    return;
end

if ~isempty(fs) && fs <= 0
    error('preprocessAudio:InvalidSampleRate', 'Sample rate must be positive.');
end

x = double(x);
x(~isfinite(x)) = 0;

if isvector(x)
    x = x(:);
elseif ismatrix(x) && size(x, 2) > 1
    x = mean(x, 2);
else
    x = x(:);
end

x(~isfinite(x)) = 0;

removeDC = getAudioOption(config, 'removeDC', false);
if removeDC && ~isempty(x)
    x = x - mean(x);
end

normalizeInput = getAudioOption(config, 'normalizeInput', false);
if normalizeInput && ~isempty(x)
    targetPeak = getAudioOption(config, 'normalizeTargetPeak', 0.99);
    targetPeak = max(0, min(abs(double(targetPeak)), 1));
    currentPeak = max(abs(x));
    if currentPeak > eps && targetPeak > 0
        x = x / currentPeak * targetPeak;
    end
end
end

function value = getAudioOption(config, fieldName, defaultValue)
if isfield(config, 'audio') && isfield(config.audio, fieldName)
    value = config.audio.(fieldName);
else
    value = defaultValue;
end
end

function config = fillAudioDefaults(config)
defaults = makeDefaultConfig();
if ~isfield(config, 'audio') || isempty(config.audio)
    config.audio = defaults.audio;
    return;
end

audioFields = fieldnames(defaults.audio);
for k = 1:numel(audioFields)
    name = audioFields{k};
    if ~isfield(config.audio, name)
        config.audio.(name) = defaults.audio.(name);
    end
end
end
