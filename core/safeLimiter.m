function y = safeLimiter(x, config)
%SAFELIMITER Keep output inside the configured peak range.
%   This is a simple safety guard for framework testing. It is not a final
%   loudness, compression, or mastering algorithm. Current stage uses a hard
%   limiter only.

if nargin < 2 || isempty(config)
    config = makeDefaultConfig();
end

y = double(x);
y = y(:);
y(~isfinite(y)) = 0;

limitEnabled = true;
limitRange = [-1, 1];

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
end

if limitEnabled
    low = min(limitRange);
    high = max(limitRange);
    if low == high
        low = -1;
        high = 1;
    end
    y = min(max(y, low), high);
end
end
