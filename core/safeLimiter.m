function y = safeLimiter(x, config)
%SAFELIMITER Final finite-value guard and peak limiter.
%   Modes:
%       hard - strict clipping;
%       soft - transparent linear region followed by a soft knee.
%
%   The limiter is a safety stage, not an automatic loudness normalizer.

if nargin < 2 || isempty(config)
    config = makeDefaultConfig();
end

y = double(x);
y = y(:);
y(~isfinite(y)) = 0;

limitEnabled = true;
limitRange = [-1, 1];
limiterMode = 'hard';
softDrive = 1.15;

if isfield(config, 'output')
    if isfield(config.output, 'limitEnabled')
        limitEnabled = logical(config.output.limitEnabled);
    end
    if isfield(config.output, 'limitRange')
        r = double(config.output.limitRange);
        if numel(r) >= 2 && all(isfinite(r(1:2)))
            limitRange = r(1:2);
        end
    elseif isfield(config.output, 'peakLimit')
        p = max(abs(double(config.output.peakLimit)), eps);
        limitRange = [-p, p];
    end
    if isfield(config.output, 'limiterMode') && ~isempty(config.output.limiterMode)
        limiterMode = lower(char(config.output.limiterMode));
    end
    if isfield(config.output, 'softDrive') && ...
            isfinite(double(config.output.softDrive))
        softDrive = max(1.0, double(config.output.softDrive));
    end
end

if ~limitEnabled || isempty(y)
    return;
end

low = min(limitRange);
high = max(limitRange);
if ~isfinite(low) || ~isfinite(high) || low >= high
    low = -1;
    high = 1;
end

switch limiterMode
    case 'soft'
        center = (low + high) / 2;
        halfRange = max((high - low) / 2, eps);
        z = (y - center) / halfRange;
        signZ = sign(z);
        absZ = abs(z);
        knee = 0.82;
        above = absZ > knee;
        if any(above)
            u = (absZ(above) - knee) / max(1 - knee, eps);
            u = min(max(u, 0), 1);
            % Power-knee mapping stays below the hard-limiter line inside
            % the knee region, is monotonic, and reaches the peak exactly.
            shaped = knee + (1 - knee) * (u .^ softDrive);
            absZ(above) = shaped;
        end
        z = signZ .* absZ;
        y = center + halfRange * z;

    otherwise
        y = min(max(y, low), high);
end

y(~isfinite(y)) = 0;
end
