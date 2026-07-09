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

cfg = makeAppConfig(struct('voice', 'elderly', 'fx', 'walkie', 'space', 'stage', 'am', 'modulate'));
assert(cfg.voice.enabled && strcmp(cfg.voice.type, 'elder'), 'elderly UI mode should map to backend elder.');
assert(cfg.fx.enabled && strcmp(cfg.fx.type, 'walkie_talkie'), 'walkie UI mode should map to backend walkie_talkie.');
assert(cfg.space.enabled && strcmp(cfg.space.type, 'bathroom'), 'stage should map to backend bathroom compatibility mode.');
assert(cfg.modDemod.enabled && strcmp(cfg.modDemod.type, 'am_modulate'), 'modulate should map to am_modulate.');

cfg = makeAppConfig('voice', 'robot', 'fx', 'robot', 'space', 'cave', 'noise', 'hum50', 'filter', 'notch50', 'am', 'demodulate');
assert(strcmp(cfg.voice.type, 'robot_voice'), 'robot voice should map to robot_voice.');
assert(strcmp(cfg.fx.type, 'robot'), 'robot FX should remain robot.');
assert(strcmp(cfg.space.type, 'cave'), 'cave should be a supported hidden App choice.');
assert(strcmp(cfg.noise.type, 'hum50'), 'hum50 should be supported.');
assert(strcmp(cfg.filter.type, 'notch50'), 'notch50 should be supported.');
assert(strcmp(cfg.modDemod.type, 'am_demodulate'), 'demodulate should map to am_demodulate.');

samplePath = pickSample(fullfile(projectRoot, 'samples'));
[xRaw, fs] = audioread(samplePath);
x = preprocessAudio(xRaw, fs, makeAppConfig());
x = x(1:min(numel(x), round(2.0 * fs)));

chains = {
    struct('filter', 'voice_enhance', 'fx', 'telephone')
    struct('voice', 'child', 'space', 'bathroom')
    struct('voice', 'elderly', 'fx', 'gramophone')
    struct('voice', 'anonymous', 'fx', 'walkie')
    struct('voice', 'robot', 'fx', 'bitcrusher')
    struct('fx', 'radio', 'space', 'cave')
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
