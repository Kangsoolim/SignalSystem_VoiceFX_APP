%TEST_03_FILTER_VISUALIZATION Validate traditional filters and report plots.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1-1/fs).';
clean = 0.25 * sin(2 * pi * 440 * t);
hum = 0.06 * sin(2 * pi * 50 * t);
rng(7, 'twister');
noisy = clean + hum + 0.015 * randn(size(clean));
probe = clean + hum + 0.12 * sin(2 * pi * 1000 * t) + ...
    0.08 * sin(2 * pi * 5000 * t) + 0.05 * sin(2 * pi * 6500 * t);

config = makeDefaultConfig();
assert(~config.filter.useZeroPhase, 'Default filter path must keep useZeroPhase disabled for realtime/state processing.');
filterTypes = {'none', 'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};

for k = 1:numel(filterTypes)
    filterConfig = config.filter;
    filterConfig.enabled = true;
    filterConfig.type = filterTypes{k};
    filterConfig.mode = 'legacy_value_should_not_override_type';
    filterConfig.order = 4;
    filterConfig.lowCutoff = 80;
    filterConfig.highCutoff = 3400;
    filterConfig.notchFreq = 50;
    filterConfig.bandwidth = 2;
    filterConfig.useZeroPhase = false;

    state = initProcessState(config);
    [y, state] = applyDenoiseFilter(noisy, fs, filterConfig, state);

    assert(isstruct(state), 'Filter must return a state struct.');
    assert(numel(y) == numel(noisy), 'Filter output length must match input.');
    assert(isa(y, 'double'), 'Filter output must be double.');
    assert(iscolumn(y), 'Filter output must be a column vector.');
    assert(all(isfinite(y)), 'Filter output must not contain NaN or Inf.');
    if ~strcmp(filterTypes{k}, 'none')
        assert(isfield(state.filter, 'zi') && ~isempty(state.filter.zi), ...
            'Realtime filter path should keep zi state when useZeroPhase is false.');
    end

    info = analyzeSpectrum(y, fs, config.display);
    assert(isstruct(info), 'Filtered spectrum info must be a struct.');
    assert(numel(info.f) == numel(info.mag), 'Filtered spectrum f/mag lengths must match.');
    assert(~isempty(info.f) && info.f(1) == 0, 'Filtered spectrum frequency vector must start at 0.');
    assert(info.f(end) <= fs / 2 + fs / numel(y), 'Filtered spectrum must not exceed Nyquist.');
end

assertBandAttenuation(probe, fs, 'highpass', 50, -8);
assertBandAttenuation(probe, fs, 'lowpass', 5000, -10);
assertBandAttenuation(probe, fs, 'bandpass', 50, -8);
assertBandAttenuation(probe, fs, 'bandpass', 6500, -10);
assertBandAttenuation(probe, fs, 'notch50', 50, -12);

voiceConfig = config.filter;
voiceConfig.enabled = true;
voiceConfig.type = 'voice_enhance';
voiceConfig.useZeroPhase = false;
[voiceY, ~] = applyDenoiseFilter(probe, fs, voiceConfig, initProcessState(config));
assert(attenuationDb(probe, voiceY, fs, 50) < -6, 'voice_enhance should reduce low hum/rumble.');
assert(attenuationDb(probe, voiceY, fs, 6500) < -6, 'voice_enhance should reduce harsh high-frequency content.');
assert(attenuationDb(probe, voiceY, fs, 1000) > -3.5, 'voice_enhance should preserve core speech-band energy.');
assert(attenuationDb(probe, voiceY, fs, 5000) > -10, 'voice_enhance should avoid making the voice too muffled.');
assert(rmsValue(voiceY) < 1.1 * rmsValue(probe), 'voice_enhance should remain lightweight and avoid obvious gain/distortion.');

legacyConfig = config.filter;
legacyConfig.enabled = true;
legacyConfig.type = '';
legacyConfig.mode = 'highpass';
[legacyY, legacyState] = applyDenoiseFilter(noisy, fs, legacyConfig, initProcessState(config));
assert(isstruct(legacyState), 'Legacy filter mode must return state.');
assert(numel(legacyY) == numel(noisy), 'Legacy filter output length must match input.');
assert(all(isfinite(legacyY)), 'Legacy filter output must be finite.');

frameConfig = config;
frameConfig.filter.enabled = true;
frameConfig.filter.type = 'notch50';
[frameY, frameState] = processAudioFrame(noisy(1:333), fs, frameConfig);
assert(isstruct(frameState), 'Frame filtering must return state.');
assert(numel(frameY) == 333, 'Frame filtering output length must match input.');
assert(all(isfinite(frameY)), 'Frame filtering output must be finite.');

plotConfig = config.display;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = fullfile(projectRoot, 'results', 'figures');
plotConfig.figureName = 'test_03_filter_visualization.png';
plotConfig.useDb = true;
plotConfig.maxDurationToPlot = 0.2;

filterConfig = config.filter;
filterConfig.enabled = true;
filterConfig.type = 'notch50';
[filteredForPlot, ~] = applyDenoiseFilter(noisy, fs, filterConfig, initProcessState(config));
plotInfo = plotSignalInfo(noisy, filteredForPlot, fs, plotConfig);

assert(isstruct(plotInfo), 'plotSignalInfo must return a struct.');
assert(isfield(plotInfo, 'figureSaved') && plotInfo.figureSaved, 'plotSignalInfo should report saved figure.');
assert(isfield(plotInfo, 'figurePath') && exist(plotInfo.figurePath, 'file') == 2, 'Saved figure file should exist.');
assert(isfield(plotInfo, 'input') && isfield(plotInfo, 'output'), 'plotInfo should include input/output spectra.');

disp('test_03_filter_visualization passed: filters and report visualization work.');

function assertBandAttenuation(x, fs, filterType, frequency, maxDb)
config = makeDefaultConfig();
filterConfig = config.filter;
filterConfig.enabled = true;
filterConfig.type = filterType;
filterConfig.useZeroPhase = false;
[y, ~] = applyDenoiseFilter(x, fs, filterConfig, initProcessState(config));
actualDb = attenuationDb(x, y, fs, frequency);
assert(actualDb < maxDb, sprintf('%s should attenuate %.0f Hz by at least %.1f dB, got %.2f dB.', ...
    filterType, frequency, abs(maxDb), actualDb));
end

function db = attenuationDb(x, y, fs, frequency)
before = magnitudeAt(x, fs, frequency);
after = magnitudeAt(y, fs, frequency);
db = 20 * log10(max(after, eps) / max(before, eps));
end

function value = magnitudeAt(x, fs, frequency)
x = double(x(:));
n = numel(x);
spec = abs(fft(x));
bin = round(frequency / fs * n) + 1;
bin = min(max(bin, 1), n);
value = spec(bin) / max(n, 1);
end

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end
