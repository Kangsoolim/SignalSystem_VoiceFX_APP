function info = analyzeSpectrum(x, fs, displayConfig)
%ANALYZESPECTRUM Compute single-sided magnitude spectrum data.
%   This function only returns analysis data. It does not draw figures or
%   interact with App Designer components.

if nargin < 3 || isempty(displayConfig)
    displayConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end

x = double(x);
x = x(:);
x(~isfinite(x)) = 0;

info = struct();
info.fs = fs;
info.numSamples = numel(x);
info.durationSeconds = 0;
info.f = [];
info.mag = [];
info.magDb = [];
info.displayConfig = displayConfig;

if isempty(fs) || fs <= 0
    error('analyzeSpectrum:InvalidSampleRate', 'Sample rate must be positive.');
end

if isempty(x)
    return;
end

info.durationSeconds = numel(x) / fs;

n = numel(x);
fftValues = fft(x);
twoSidedMag = abs(fftValues / n);

singleSideCount = floor(n / 2) + 1;
mag = twoSidedMag(1:singleSideCount);
if n > 1
    if mod(n, 2) == 0
        if numel(mag) > 2
            mag(2:end-1) = 2 * mag(2:end-1);
        end
    else
        if numel(mag) > 1
            mag(2:end) = 2 * mag(2:end);
        end
    end
end

f = (0:singleSideCount-1).' * fs / n;

dbFloor = getDisplayOption(displayConfig, 'dbFloor', -120);
magDb = 20 * log10(max(mag, 10^(double(dbFloor) / 20)));

info.f = f;
info.mag = mag;
info.magDb = magDb;
end

function value = getDisplayOption(displayConfig, fieldName, defaultValue)
if isfield(displayConfig, fieldName) && ~isempty(displayConfig.(fieldName))
    value = displayConfig.(fieldName);
else
    value = defaultValue;
end
end
