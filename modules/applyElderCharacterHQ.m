function [y, diagnostics] = applyElderCharacterHQ(x, fs, voiceConfig)
%APPLYELDERCHARACTERHQ Add subtle continuous age-style modulation offline.
%   The stage intentionally avoids random clicks, free-running hiss and hard
%   frame resets. It uses very shallow deterministic amplitude tremor and a
%   tiny continuously varying fractional delay to add age-like instability.
%   The main age impression still comes from pitch, spectral envelope,
%   excitation and dynamics shaping.

x = finiteColumn(x);
diagnostics = struct('status','ok', ...
    'tremorDepth',0, 'tremorRateHz',0, 'microDelayMs',0);
if isempty(x)
    y = x;
    diagnostics.status = 'empty';
    return;
end

validateattributes(fs, {'numeric'}, ...
    {'scalar','real','finite','positive'}, mfilename, 'fs');

depth = clamp(getParam(voiceConfig, 'elderTremorDepth', 0.018), 0, 0.04);
rate = clamp(getParam(voiceConfig, 'elderTremorRateHz', 4.8), 2.5, 8.0);
microDelayMs = clamp(getParam(voiceConfig, 'elderMicroDelayMs', 0.12), 0, 0.30);

diagnostics.tremorDepth = depth;
diagnostics.tremorRateHz = rate;
diagnostics.microDelayMs = microDelayMs;

n = (0:numel(x)-1).';
t = n/fs;

% Two low-rate components avoid a perfectly periodic tremolo while remaining
% deterministic and continuous.
amp = 1 - 0.65*depth + ...
    0.55*depth*sin(2*pi*rate*t) + ...
    0.18*depth*sin(2*pi*0.63*t + 0.7);
amp = min(max(amp, 0.90), 1.04);
y = x .* amp;

% Tiny delay modulation creates a few cents of slow pitch instability. The
% query is clamped at both ends, so no NaN or zero padding click is created.
if microDelayMs > 0
    delaySamples = microDelayMs*1e-3*fs .* ...
        sin(2*pi*(rate*0.96)*t + 0.35);
    query = (1:numel(y)).' - delaySamples;
    query = min(max(query, 1), numel(y));
    warped = interp1((1:numel(y)).', y, query, 'linear');
    warped(~isfinite(warped)) = 0;
    y = 0.30*y + 0.70*warped;
end

y = limitedRmsMatch(y, x, 0.8);
y = finiteColumn(y);
end

function y = limitedRmsMatch(y, reference, maxCorrectionDb)
rmsY = sqrt(mean(y.^2));
rmsRef = sqrt(mean(reference.^2));
if rmsY <= 1e-8 || rmsRef <= 1e-8
    return;
end
maxGain = 10^(abs(maxCorrectionDb)/20);
gain = min(max(rmsRef/rmsY, 1/maxGain), maxGain);
y = y*gain;
end

function value = getParam(config, name, defaultValue)
if isstruct(config) && isfield(config,'params') && ...
        isstruct(config.params) && isfield(config.params,name) && ...
        ~isempty(config.params.(name))
    value = double(config.params.(name));
else
    value = double(defaultValue);
end
end

function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end
function x = finiteColumn(x)
x = double(x(:));
x(~isfinite(x)) = 0;
end
