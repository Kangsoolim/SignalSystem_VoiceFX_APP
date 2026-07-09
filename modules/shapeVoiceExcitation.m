function [yFrame, state] = shapeVoiceExcitation(xFrame, fs, voiceConfig, state)
%SHAPEVOICEEXCITATION Stateful excitation and spectral-tilt shaping.
%   This lightweight stage changes source-like qualities after pitch and
%   envelope mapping. It uses bounded saturation, tilt shaping, subtle airy
%   residual control and optional very low-depth roughness modulation.

x = cleanColumn(xFrame);
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
if ~isfield(state.voice, 'excitation') || isempty(state.voice.excitation)
    state.voice.excitation = struct();
end
ex = state.voice.excitation;
if ~isfield(ex, 'lpPrev'), ex.lpPrev = 0; end
if ~isfield(ex, 'lastHigh'), ex.lastHigh = 0; end

warmth = clamp01(getParam(voiceConfig, 'excitationWarmth', 0.10));
breathiness = clamp01(getParam(voiceConfig, 'breathiness', 0.02));
roughness = clamp01(getParam(voiceConfig, 'styleRoughness', 0.02));
tiltDb = clamp(getParam(voiceConfig, 'spectralTiltDb', 0), -4, 4);

[low, ex.lpPrev] = onePoleLowpass(x, fs, min(2500, 0.32*fs), ex.lpPrev);
high = x - low;

% Gentle saturation adds harmonic density for warm styles without using a
% hard clipper. Blend depth is deliberately limited.
drive = 1.0 + 1.6 * warmth;
sat = tanh(drive*x) / tanh(drive);
y = (1 - 0.24*warmth) .* x + (0.24*warmth) .* sat;

% Spectral tilt is applied as complementary broad-band weighting.
highGain = 10^(tiltDb/20);
lowGain = 10^(-0.25*tiltDb/20);
y = lowGain .* low + highGain .* (y - low);

% Airy residual: a decorrelated high-frequency difference derived from the
% signal itself, so the stage stays deterministic and does not inject a
% free-running hiss floor during silence.
delayedHigh = [ex.lastHigh; high(1:end-1)];
ex.lastHigh = high(end);
airy = high - 0.55 * delayedHigh;
envelope = min(abs(x) / max(sqrt(mean(x.^2)), 1e-6), 2.5) / 2.5;
y = y + 0.12 * breathiness .* envelope .* airy;

% Elder-style roughness uses a very shallow low-rate modulation. The depth
% is capped so this cannot become a robot/tremolo effect.
if roughness > 0.001
    if isfield(state.voice, 'sampleIndex')
        sampleIndex = double(state.voice.sampleIndex);
    else
        sampleIndex = 0;
    end
    n = sampleIndex + (0:numel(x)-1).';
    modRate = getParam(voiceConfig, 'roughnessRateHz', 4.6);
    depth = min(0.035, 0.035 * roughness);
    y = y .* (1 - depth + depth * sin(2*pi*modRate*n/fs));
end

yFrame = tanh(1.03*y) / tanh(1.03);
state.voice.excitation = ex;
end

function [y, prev] = onePoleLowpass(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2*pi*cutoff/fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1-alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end
function value = getParam(config, name, defaultValue)
if isstruct(config) && isfield(config, 'params') && ...
        isstruct(config.params) && isfield(config.params, name) && ...
        ~isempty(config.params.(name))
    value = config.params.(name);
else
    value = defaultValue;
end
end
function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end
function value = clamp01(value)
value = clamp(value, 0, 1);
end
function x = cleanColumn(x)
x = double(x(:));
x(~isfinite(x)) = 0;
end
