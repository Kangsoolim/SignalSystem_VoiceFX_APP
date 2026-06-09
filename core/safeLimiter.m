function y = safeLimiter(x, config)
%SAFELIMITER Keep output inside the configured peak range.
%   This is a simple safety guard for framework testing. It is not a final
%   loudness, compression, or mastering algorithm. Default mode is the
%   original hard limiter; optional soft mode is available through
%   config.output.limiterMode = 'soft'.

if nargin < 2 || isempty(config)
    config = makeDefaultConfig();
end

y = double(x);
y = y(:);
y(~isfinite(y)) = 0;

limitEnabled = true;
limitRange = [-1, 1];
limiterMode = 'hard';

if isfield(config, 'output')
    if isfield(config.output, 'limitEnabled')
        limitEnabled = logical(config.output.limitEnabled);
    end
    if isfield(config.output, 'limitRange')
        candidateRange = double(config.output.limitRange);
        if numel(candidateRange) >= 2 && all(isfinite(candidateRange(1:2)))
            limitRange = candidateRange(1:2);
        end
    elseif isfield(config.output, 'peakLimit')
        peakLimit = max(abs(double(config.output.peakLimit)), eps);
        limitRange = [-peakLimit, peakLimit];
    end
    if isfield(config.output, 'limiterMode') && ~isempty(config.output.limiterMode)
        limiterMode = lower(char(config.output.limiterMode));
    end
end

if limitEnabled
    low = min(limitRange);
    high = max(limitRange);
    if low == high
        low = -1;
        high = 1;
    end
    switch limiterMode
        case 'soft'
            center = (low + high) / 2;
            halfRange = max((high - low) / 2, eps);
            y = center + halfRange * tanh((y - center) / halfRange);
        otherwise
            y = min(max(y, low), high);
    end
end
end
