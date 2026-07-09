%TEST_11_APP_BACKEND_CONFIG Validate App selection-to-backend config mapping.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

cfg = makeAppConfig();
assert(isstruct(cfg), 'makeAppConfig must return a struct.');
assert(isfield(cfg, 'noise') && isfield(cfg, 'filter') && isfield(cfg, 'voice'), 'Config must preserve backend sections.');
assert(~cfg.noise.enabled && strcmp(cfg.noise.type, 'none'), 'Default noise should be off.');
assert(~cfg.fx.enabled && strcmp(cfg.fx.type, 'none'), 'Default FX should be off.');
assert(strcmp(cfg.output.limiterMode, 'soft'), 'App config should use soft output safety.');

visibleVoiceModes = {'none', 'male_deep_gentle', 'female_gentle_sweet', 'child_bright_soft', 'elder_warm_steady'};
visibleFxModes = {'none', 'telephone', 'radio', 'lofi', 'bitcrusher', 'gramophone', 'robot'};
visibleSpaceModes = {'none', 'delay', 'bathroom', 'cave'};

for k = 1:numel(visibleVoiceModes)
    cfg = makeAppConfig('voice', visibleVoiceModes{k});
    assert(strcmp(cfg.voice.type, visibleVoiceModes{k}), 'Visible voice mode should map directly.');
end
for k = 1:numel(visibleFxModes)
    cfg = makeAppConfig('fx', visibleFxModes{k});
    assert(strcmp(cfg.fx.type, visibleFxModes{k}), 'Visible FX mode should map directly.');
end
for k = 1:numel(visibleSpaceModes)
    cfg = makeAppConfig('space', visibleSpaceModes{k});
    assert(strcmp(cfg.space.type, visibleSpaceModes{k}), 'Visible space mode should map directly.');
end

aliasCases = {
    'male', 'male_deep_gentle'
    'female', 'female_gentle_sweet'
    'child', 'child_bright_soft'
    'elderly', 'elder_warm_steady'
    'elder', 'elder_warm_steady'
    'anonymous', 'anonymous'
    'robot', 'none'
};
for k = 1:size(aliasCases, 1)
    aliasCfg = makeAppConfig('voice', aliasCases{k, 1});
    assert(strcmp(aliasCfg.voice.type, aliasCases{k, 2}), 'Voice alias should map to a safe backend mode.');
end

cfg = makeAppConfig('voice', 'elderly', 'fx', 'robot', 'space', 'cave', 'noise', 'hum50', 'filter', 'notch50', 'am', 'demodulate');
assert(strcmp(cfg.voice.type, 'elder_warm_steady'), 'elderly compatibility mode should map to elder_warm_steady.');
assert(cfg.voice.params.adaptiveEnabled && strcmp(cfg.voice.params.engine, 'adaptive'), 'New deep voice modes should use adaptive engine.');
assert(strcmp(cfg.fx.type, 'robot'), 'robot FX should remain robot.');
assert(strcmp(cfg.space.type, 'cave'), 'cave should be supported.');
assert(strcmp(cfg.noise.type, 'hum50'), 'hum50 should be supported.');
assert(strcmp(cfg.filter.type, 'notch50'), 'notch50 should be supported.');
assert(strcmp(cfg.modDemod.type, 'am_demodulate'), 'demodulate should map to am_demodulate.');

samplePath = pickSample(fullfile(projectRoot, 'samples'));
[xRaw, fs] = audioread(samplePath);
x = preprocessAudio(xRaw, fs, makeAppConfig());
x = x(1:min(numel(x), round(2.0 * fs)));

chains = {
    struct('filter', 'voice_enhance', 'voice', 'male_deep_gentle', 'fx', 'telephone')
    struct('filter', 'voice_enhance', 'voice', 'female_gentle_sweet', 'fx', 'lofi')
    struct('voice', 'child_bright_soft', 'space', 'bathroom')
    struct('voice', 'elder_warm_steady', 'fx', 'gramophone')
    struct('voice', 'male_deep_gentle', 'space', 'cave')
    struct('voice', 'none', 'fx', 'robot')
    struct('voice', 'male_deep_gentle', 'fx', 'bitcrusher', 'space', 'delay', 'am', 'modulate')
};

for k = 1:numel(chains)
    chainCfg = makeAppConfig(chains{k});
    y = processAudioFile(x, fs, chainCfg);
    assert(numel(y) == numel(x), 'App backend chain output length must match input.');
    assert(all(isfinite(y)), 'App backend chain output must be finite.');
    assert(max(abs(y)) <= 1.000001, 'App backend chain output must stay bounded.');
end

disp('test_11_app_backend_config passed: App config mapping and processing chains are valid.');

function samplePath = pickSample(samplesDir)
files = dir(fullfile(samplesDir, '*.wav'));
assert(~isempty(files), 'At least one wav sample is required under samples/.');
samplePath = fullfile(files(1).folder, files(1).name);
end
