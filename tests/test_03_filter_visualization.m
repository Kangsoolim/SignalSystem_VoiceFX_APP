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

config = makeDefaultConfig();
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

    info = analyzeSpectrum(y, fs, config.display);
    assert(isstruct(info), 'Filtered spectrum info must be a struct.');
    assert(numel(info.f) == numel(info.mag), 'Filtered spectrum f/mag lengths must match.');
    assert(~isempty(info.f) && info.f(1) == 0, 'Filtered spectrum frequency vector must start at 0.');
    assert(info.f(end) <= fs / 2 + fs / numel(y), 'Filtered spectrum must not exceed Nyquist.');
end

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
