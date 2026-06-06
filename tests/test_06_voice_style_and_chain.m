%TEST_06_VOICE_STYLE_AND_CHAIN Validate voice styles and chained presets.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.2-1/fs).';
x = 0.30 * sin(2 * pi * 180 * t) + ...
    0.18 * sin(2 * pi * 360 * t) + ...
    0.10 * sin(2 * pi * 950 * t) + ...
    0.06 * sin(2 * pi * 2100 * t);
x = x(:);

config = makeDefaultConfig();
assert(~config.voice.enabled, 'Default voice.enabled must be false.');
assert(strcmp(config.voice.type, 'none'), 'Default voice.type must be none.');

[defaultY, defaultState] = processAudioFrame(x, fs, config);
assert(isstruct(defaultState), 'Default voice chain must return state.');
assert(numel(defaultY) == numel(x), 'Default voice chain output length must match input.');
assert(max(abs(defaultY - x)) < 1e-12, 'Default disabled voice path should not change signal.');

voiceModes = {'none', 'male', 'female', 'child', 'elder', 'anonymous', 'robot_voice'};
voiceOutputs = struct();
for k = 1:numel(voiceModes)
    voiceConfig = config.voice;
    voiceConfig.enabled = true;
    voiceConfig.type = voiceModes{k};
    voiceConfig.mode = 'legacy_value_should_not_override_type';
    voiceConfig.mix = 1.0;
    voiceConfig.intensity = 0.6;
    voiceConfig.pitchShift = 0;
    voiceConfig.lowGain = 0;
    voiceConfig.highGain = 0;
    voiceConfig.roughness = 0.2;
    voiceConfig.modFreq = 35;

    [y, voiceState] = applyVoiceStyle(x, fs, voiceConfig, initProcessState(config));
    assert(isstruct(voiceState), 'Voice style must return state.');
    assert(numel(y) == numel(x), 'Voice style output length must match input.');
    assert(isa(y, 'double'), 'Voice style output must be double.');
    assert(iscolumn(y), 'Voice style output must be a column vector.');
    assert(all(isfinite(y)), 'Voice style output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'Voice style output should stay in a safe range.');

    voiceOutputs.(voiceModes{k}) = y;
end

chainPresets = {
    'anonymous', 'telephone', 'none';
    'child', 'lofi', 'reverb';
    'robot_voice', 'bitcrusher', 'delay'
};
chainOutputs = struct();
for k = 1:size(chainPresets, 1)
    voiceName = chainPresets{k, 1};
    fxName = chainPresets{k, 2};
    spaceName = chainPresets{k, 3};

    chainConfig = config;
    chainConfig.voice.enabled = true;
    chainConfig.voice.type = voiceName;
    chainConfig.voice.mix = 1.0;
    chainConfig.voice.intensity = 0.65;
    chainConfig.fx.enabled = ~strcmp(fxName, 'none');
    chainConfig.fx.type = fxName;
    chainConfig.fx.mix = 0.9;
    chainConfig.fx.intensity = 0.55;
    chainConfig.space.enabled = ~strcmp(spaceName, 'none');
    chainConfig.space.type = spaceName;
    chainConfig.space.mix = 0.35;
    chainConfig.space.delayTime = 0.07;
    chainConfig.space.feedback = 0.30;
    chainConfig.space.reverbAmount = 0.45;

    [y, chainState] = processAudioFrame(x(1:901), fs, chainConfig);
    assert(isstruct(chainState), 'Voice + FX + space chain must return state.');
    assert(isfield(chainState, 'voice') && isfield(chainState, 'fx') && isfield(chainState, 'space'), 'Chain state must include voice/fx/space.');
    assert(numel(y) == 901, 'Voice + FX + space chain output length must match input.');
    assert(isa(y, 'double'), 'Voice + FX + space chain output must be double.');
    assert(iscolumn(y), 'Voice + FX + space chain output must be a column vector.');
    assert(all(isfinite(y)), 'Voice + FX + space chain output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'Voice + FX + space chain output should stay in limiter range.');

    key = [voiceName, '_', fxName, '_', spaceName];
    chainOutputs.(key) = y;
end

originalInfo = analyzeSpectrum(x, fs, config.display);
anonymousInfo = analyzeSpectrum(voiceOutputs.anonymous, fs, config.display);
chainInfo = analyzeSpectrum(chainOutputs.child_lofi_reverb, fs, config.display);
assert(numel(originalInfo.f) == numel(originalInfo.mag), 'Original spectrum f/mag lengths must match.');
assert(numel(anonymousInfo.f) == numel(anonymousInfo.mag), 'Anonymous spectrum f/mag lengths must match.');
assert(numel(chainInfo.f) == numel(chainInfo.mag), 'Chain spectrum f/mag lengths must match.');
assert(all(isfinite(originalInfo.magDb)) && all(isfinite(anonymousInfo.magDb)) && all(isfinite(chainInfo.magDb)), 'Spectra must be finite.');

plotConfig = config.display;
plotConfig.enabled = true;
plotConfig.saveFigure = true;
plotConfig.outputDir = fullfile(projectRoot, 'results', 'figures');
plotConfig.useDb = true;
plotConfig.maxDurationToPlot = 0.08;

plotConfig.figureName = 'test_06_voice_style_comparison.png';
voicePlotInfo = plotSignalInfo(x, voiceOutputs.anonymous, fs, plotConfig);

plotConfig.figureName = 'test_06_voice_fx_chain.png';
chainPlotInfo = plotSignalInfo(x(1:901), chainOutputs.child_lofi_reverb, fs, plotConfig);

assert(voicePlotInfo.figureSaved && exist(voicePlotInfo.figurePath, 'file') == 2, 'Voice style comparison figure should be saved.');
assert(chainPlotInfo.figureSaved && exist(chainPlotInfo.figurePath, 'file') == 2, 'Voice + FX chain figure should be saved.');

disp('test_06_voice_style_and_chain passed: voice styles and chains work.');
