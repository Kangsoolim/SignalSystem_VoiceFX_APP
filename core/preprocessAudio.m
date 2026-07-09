function x = preprocessAudio(x, fs, config)
%PREPROCESSAUDIO Robust input conditioning shared by file and realtime paths.
%   The function keeps preprocessing deliberately conservative:
%   - convert to finite double precision;
%   - robust mono downmix with anti-cancellation fallback;
%   - optional DC removal and static input gain;
%   - optional full-frame peak normalization;
%   - optional emergency peak protection without per-frame pumping.
%
%   Realtime noise suppression and rumble/hum removal belong in
%   applyDenoiseFilter so their cross-frame state is preserved.

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

if ~isempty(fs) && (~isscalar(fs) || ~isfinite(fs) || fs <= 0)
    error('preprocessAudio:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

x = double(x);
x(~isfinite(x)) = 0;

if isvector(x)
    x = x(:);
elseif ismatrix(x) && size(x, 2) > 1
    x = robustMonoDownmix(x, getAudioOption(config, 'monoMode', 'energy_weighted'));
else
    x = x(:);
end

x(~isfinite(x)) = 0;

if getAudioOption(config, 'removeDC', false) && ~isempty(x)
    x = x - mean(x);
end

inputGainDb = double(getAudioOption(config, 'inputGainDb', 0));
if isfinite(inputGainDb) && abs(inputGainDb) > eps
    x = x * 10 ^ (inputGainDb / 20);
end

if getAudioOption(config, 'normalizeInput', false) && ~isempty(x)
    targetPeak = clampAbs(getAudioOption(config, 'normalizeTargetPeak', 0.99), 0, 1);
    currentPeak = max(abs(x));
    if currentPeak > eps && targetPeak > 0
        x = x * (targetPeak / currentPeak);
    end
end

% Emergency protection is a single constant gain for this call. It is not a
% compressor and does not chase frame RMS, so it avoids rapid loudness pumping.
if getAudioOption(config, 'protectInputPeak', true) && ~isempty(x)
    protectPeak = clampAbs(getAudioOption(config, 'protectPeak', 0.995), 0.1, 1.0);
    currentPeak = max(abs(x));
    if currentPeak > protectPeak
        x = x * (protectPeak / currentPeak);
    end
end

x = x(:);
x(~isfinite(x)) = 0;
end

function mono = robustMonoDownmix(x, mode)
mode = lower(char(mode));
numChannels = size(x, 2);
if numChannels == 1
    mono = x(:, 1);
    return;
end

channelRms = sqrt(mean(x .^ 2, 1));
[dominantRms, dominantIndex] = max(channelRms);

switch mode
    case 'mean'
        mono = mean(x, 2);

    case 'dominant'
        mono = x(:, dominantIndex);

    otherwise
        % Energy-weighted downmix favors the clean/strong microphone channel.
        % If anti-phase channels cancel strongly, fall back to the dominant
        % channel rather than returning a near-silent mixture.
        weightSum = sum(channelRms);
        if weightSum <= eps
            mono = mean(x, 2);
        else
            weights = channelRms / weightSum;
            mono = x * weights(:);
            monoRms = sqrt(mean(mono .^ 2));
            if dominantRms > eps && monoRms < 0.20 * dominantRms
                mono = x(:, dominantIndex);
            end
        end
end

mono = mono(:);
end

function value = getAudioOption(config, fieldName, defaultValue)
if isfield(config, 'audio') && isfield(config.audio, fieldName) && ...
        ~isempty(config.audio.(fieldName))
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

fields = fieldnames(defaults.audio);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config.audio, name)
        config.audio.(name) = defaults.audio.(name);
    end
end
end

function value = clampAbs(value, low, high)
value = abs(double(value));
if isempty(value) || ~isfinite(value)
    value = high;
end
value = min(max(value, low), high);
end
