%TEST_FX_PRESETS Validate curated Stage 4 M06 vocal FX presets.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeDefaultConfig();

assert(isfield(config.fx, 'presets') && isstruct(config.fx.presets), 'FX presets must be defined.');
assert(ismember('walkie_talkie', config.fx.hiddenPresets), 'Walkie-talkie should be hidden after curation.');
assert(ismember('lofi', config.fx.hiddenPresets), 'Lo-fi should be hidden after curation.');
assert(ismember('robot', config.fx.hiddenPresets), 'Robot should stay hidden/heavy by default.');
assert(~ismember('walkie_talkie', config.fx.displayPresets), 'Walkie-talkie should not be in the default display list.');
assert(~ismember('lofi', config.fx.displayPresets), 'Lo-fi should not be in the default display list.');
assert(~ismember('robot', config.fx.displayPresets), 'Robot should not be in the default display preset list.');

samplePath = pickRealSample(fullfile(projectRoot, 'samples'));
[xRaw, fs] = audioread(samplePath);
x = preprocessAudio(xRaw, fs, makeAuditionConfig());
x = limitDuration(x, fs, 4.0);
x = safeLimiter(x, makeAuditionConfig());

fxModes = {'telephone', 'radio', 'bitcrusher', 'gramophone', 'robot'};
outputs = struct();
for k = 1:numel(fxModes)
    mode = fxModes{k};
    fxConfig = config.fx;
    fxConfig.enabled = true;
    fxConfig.type = mode;
    fxConfig.mode = 'legacy_value_should_not_override_type';

    [y, fxState] = applyVocalFX(x, fs, fxConfig, initProcessState(config));
    assert(isstruct(fxState), 'FX state must be returned.');
    assert(numel(y) == numel(x), 'FX output length must match input.');
    assert(isa(y, 'double') && iscolumn(y), 'FX output must be a double column vector.');
    assert(all(isfinite(y)), 'FX output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'FX output must stay inside limiter range.');
    assert(rmsValue(y) > 0.04 * max(rmsValue(x), eps), 'FX output should not collapse to near silence.');
    assert(rmsValue(y - x) > 0.015 * max(rmsValue(x), eps), 'Each FX preset should create an audible real-sample difference.');

    outputs.(mode) = y;
end

assert(passbandFraction(outputs.telephone, fs, 300, 3400) > 0.78, ...
    'Telephone preset should have a clear 300-3400 Hz band-limited spectrum.');
assert(passbandFraction(outputs.radio, fs, 180, 4200) > 0.75, ...
    'Radio preset should have a clear device-band spectrum.');

assert(highBandFraction(outputs.bitcrusher, fs, 6500) < 0.26, ...
    'Bitcrusher default should stay relatively mild, not overly piercing.');
assert(passbandFraction(outputs.gramophone, fs, 180, 4300) > 0.72, ...
    'Gramophone should keep a narrow old-record voice band.');
assert(rmsValue(outputs.robot - x) > 0.04 * max(rmsValue(x), eps), ...
    'Robot heavy preset should remain stylistically clear even while hidden.');

radioDiff = rmsValue(outputs.radio - x) / max(rmsValue(x), eps);
bitcrusherDiff = rmsValue(outputs.bitcrusher - x) / max(rmsValue(x), eps);
gramophoneDiff = rmsValue(outputs.gramophone - x) / max(rmsValue(x), eps);
assert(radioDiff > 0.80, ...
    'Old Radio should be more than a barely narrowed original signal.');
assert(bitcrusherDiff > 0.30, ...
    'Bitcrusher Crunch should be audibly stronger than a barely changed quantizer.');
assert(gramophoneDiff > 0.45, ...
    'Gramophone should be clearly different from the original real sample.');
assert(spectralCentroid(outputs.robot, fs) < spectralCentroid(outputs.bitcrusher, fs), ...
    'Robot Bass Monotone should emphasize a lower, flatter tone than Bitcrusher Crunch.');

disp('test_fx_presets passed: Stage 4 M06 FX presets are curated and bounded.');

function samplePath = pickRealSample(samplesDir)
preferred = dir(fullfile(samplesDir, '*upbeat*.wav'));
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*spoken*.wav'));
end
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*.wav'));
end
assert(~isempty(preferred), 'At least one real wav sample is required under samples/.');
samplePath = fullfile(preferred(1).folder, preferred(1).name);
end

function config = makeAuditionConfig()
config = makeDefaultConfig();
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.82;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
end

function y = limitDuration(x, fs, maxSeconds)
x = x(:);
y = x(1:min(numel(x), max(1, round(maxSeconds * fs))));
end

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end

function value = passbandFraction(x, fs, lowCutoff, highCutoff)
[freq, mag2] = powerSpectrum(x, fs);
mask = freq >= lowCutoff & freq <= highCutoff;
value = sum(mag2(mask)) / max(sum(mag2), eps);
end

function value = highBandFraction(x, fs, lowCutoff)
[freq, mag2] = powerSpectrum(x, fs);
mask = freq >= lowCutoff;
value = sum(mag2(mask)) / max(sum(mag2), eps);
end

function value = spectralCentroid(x, fs)
[freq, mag2] = powerSpectrum(x, fs);
value = sum(freq .* mag2) / max(sum(mag2), eps);
end

function value = zeroCrossingRate(x)
x = double(x(:));
if numel(x) < 2
    value = 0;
else
    value = mean(abs(diff(sign(x))) > 0);
end
end

function [freq, mag2] = powerSpectrum(x, fs)
x = double(x(:));
n = numel(x);
spec = abs(fft(x));
count = floor(n / 2) + 1;
freq = (0:count-1).' * fs / n;
mag2 = spec(1:count) .^ 2;
end
