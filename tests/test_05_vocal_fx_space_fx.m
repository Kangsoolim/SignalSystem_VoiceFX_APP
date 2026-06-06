%TEST_05_VOCAL_FX_SPACE_FX Validate basic vocal FX, space FX, and chains.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.2-1/fs).';
x = 0.28 * sin(2 * pi * 220 * t) + ...
    0.18 * sin(2 * pi * 660 * t) + ...
    0.08 * sin(2 * pi * 1800 * t);
x = x(:);

config = makeDefaultConfig();
assert(~config.fx.enabled, 'Default fx.enabled must be false.');
assert(~config.space.enabled, 'Default space.enabled must be false.');

[defaultY, defaultState] = processAudioFrame(x, fs, config);
assert(isstruct(defaultState), 'Default chain must return state.');
assert(numel(defaultY) == numel(x), 'Default chain output length must match input.');
assert(max(abs(defaultY - x)) < 1e-12, 'Default disabled FX/space path should not change signal.');

fxModes = {'none', 'telephone', 'walkie_talkie', 'radio', 'lofi', 'bitcrusher', 'robot'};
fxOutputs = struct();
for k = 1:numel(fxModes)
    fxConfig = config.fx;
    fxConfig.enabled = true;
    fxConfig.type = fxModes{k};
    fxConfig.mode = 'legacy_value_should_not_override_type';
    fxConfig.mix = 1.0;
    fxConfig.intensity = 0.6;
    fxConfig.bitDepth = 8;
    fxConfig.modFreq = 35;
    fxConfig.drive = 1.5;

    [y, fxState] = applyVocalFX(x, fs, fxConfig, initProcessState(config));
    assert(isstruct(fxState), 'Vocal FX must return state.');
    assert(numel(y) == numel(x), 'Vocal FX output length must match input.');
    assert(isa(y, 'double'), 'Vocal FX output must be double.');
    assert(iscolumn(y), 'Vocal FX output must be a column vector.');
    assert(all(isfinite(y)), 'Vocal FX output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'Vocal FX output should stay in a safe range.');

    fxOutputs.(fxModes{k}) = y;
end

spaceModes = {'none', 'delay', 'reverb', 'bathroom', 'cave', 'stage'};
spaceOutputs = struct();
for k = 1:numel(spaceModes)
    spaceConfig = config.space;
    spaceConfig.enabled = true;
    spaceConfig.type = spaceModes{k};
    spaceConfig.mode = 'legacy_value_should_not_override_type';
    spaceConfig.mix = 0.45;
    spaceConfig.delayTime = 0.08;
    spaceConfig.feedback = 0.35;
    spaceConfig.reverbAmount = 0.5;

    [y, spaceState] = applySpaceFX(x, fs, spaceConfig, initProcessState(config));
    assert(isstruct(spaceState), 'Space FX must return state.');
    assert(numel(y) == numel(x), 'Space FX output length must match input.');
    assert(isa(y, 'double'), 'Space FX output must be double.');
    assert(iscolumn(y), 'Space FX output must be a column vector.');
    assert(all(isfinite(y)), 'Space FX output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'Space FX output should stay in a safe range.');

    spaceOutputs.(spaceModes{k}) = y;
end

chainPairs = {
    'telephone', 'reverb';
    'lofi', 'stage';
    'robot', 'delay'
};
chainOutputs = struct();
for k = 1:size(chainPairs, 1)
    fxName = chainPairs{k, 1};
    spaceName = chainPairs{k, 2};

    chainConfig = config;
    chainConfig.fx.enabled = true;
    chainConfig.fx.type = fxName;
    chainConfig.fx.mix = 1.0;
    chainConfig.fx.intensity = 0.6;
    chainConfig.space.enabled = true;
    chainConfig.space.type = spaceName;
    chainConfig.space.mix = 0.35;
    chainConfig.space.delayTime = 0.06;
    chainConfig.space.feedback = 0.32;
    chainConfig.space.reverbAmount = 0.45;

    [y, chainState] = processAudioFrame(x(1:777), fs, chainConfig);
    assert(isstruct(chainState), 'FX + space chain must return state.');
    assert(isfield(chainState, 'fx') && isfield(chainState, 'space'), 'Chain state must include fx and space fields.');
    assert(numel(y) == 777, 'FX + space chain output length must match input.');
    assert(isa(y, 'double'), 'FX + space chain output must be double.');
    assert(iscolumn(y), 'FX + space chain output must be a column vector.');
    assert(all(isfinite(y)), 'FX + space chain output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'FX + space chain output should stay in limiter range.');

    chainOutputs.([fxName, '_', spaceName]) = y;
end

originalInfo = analyzeSpectrum(x, fs, config.display);
telephoneInfo = analyzeSpectrum(fxOutputs.telephone, fs, config.display);
chainInfo = analyzeSpectrum(chainOutputs.lofi_stage, fs, config.display);
assert(numel(originalInfo.f) == numel(originalInfo.mag), 'Original spectrum f/mag lengths must match.');
assert(numel(telephoneInfo.f) == numel(telephoneInfo.mag), 'Telephone spectrum f/mag lengths must match.');
assert(numel(chainInfo.f) == numel(chainInfo.mag), 'Chain spectrum f/mag lengths must match.');
assert(all(isfinite(originalInfo.magDb)) && all(isfinite(telephoneInfo.magDb)) && all(isfinite(chainInfo.magDb)), 'Spectra must be finite.');

figureDir = fullfile(projectRoot, 'results', 'figures');
plotConfig = config.display;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = figureDir;
plotConfig.useDb = true;
plotConfig.maxDurationToPlot = 0.08;

plotConfig.figureName = 'test_05_vocal_fx_comparison.png';
fxPlotInfo = plotSignalInfo(x, fxOutputs.telephone, fs, plotConfig);

plotConfig.figureName = 'test_05_space_fx_comparison.png';
spacePlotInfo = plotSignalInfo(x, spaceOutputs.stage, fs, plotConfig);

plotConfig.figureName = 'test_05_fx_space_chain.png';
chainPlotInfo = plotSignalInfo(x(1:777), chainOutputs.lofi_stage, fs, plotConfig);

assert(fxPlotInfo.figureSaved && exist(fxPlotInfo.figurePath, 'file') == 2, 'Vocal FX comparison figure should be saved.');
assert(spacePlotInfo.figureSaved && exist(spacePlotInfo.figurePath, 'file') == 2, 'Space FX comparison figure should be saved.');
assert(chainPlotInfo.figureSaved && exist(chainPlotInfo.figurePath, 'file') == 2, 'FX + space chain figure should be saved.');

disp('test_05_vocal_fx_space_fx passed: vocal FX, space FX, and chains work.');
