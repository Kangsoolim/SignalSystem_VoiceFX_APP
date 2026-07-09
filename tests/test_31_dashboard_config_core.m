%TEST_31_DASHBOARD_CONFIG_CORE Validate Dashboard/CLI shared config mapping.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

options = struct();
options.frameLength = 512;
options.intensity = 0.74;
options.enableSpeechClean = true;
options.fxMode = 'radio';
options.fxMix = 0.63;
options.fxIntensity = 0.55;
options.spaceMode = 'bathroom';
options.spaceMix = 0.28;

config = buildRealtimeConfig('female', options);
assert(config.audio.frameLength == 512, 'Frame length mapping failed.');
assert(config.filter.enabled && strcmp(config.filter.type, 'speech_clean'), ...
    'Speech clean mapping failed.');
assert(config.voice.enabled && strcmp(config.voice.type, 'female'), ...
    'Voice mode mapping failed.');
assert(abs(config.voice.intensity - 0.74) < 1e-12, 'Voice intensity mapping failed.');
assert(config.fx.enabled && strcmp(config.fx.type, 'radio'), 'FX mapping failed.');
assert(abs(config.fx.mix - 0.63) < 1e-12, 'FX mix mapping failed.');
assert(config.space.enabled && strcmp(config.space.type, 'bathroom'), ...
    'Space mapping failed.');
assert(~config.modDemod.enabled, 'AM must remain disabled by default in realtime config.');
assert(config.output.limitEnabled, 'Realtime output limiter should remain enabled.');

noneOptions = struct('frameLength', 256, 'enableSpeechClean', false, ...
    'fxMode', 'none', 'spaceMode', 'none');
noneConfig = buildRealtimeConfig('anonymous', noneOptions);
assert(~noneConfig.filter.enabled, 'Filter should disable cleanly.');
assert(~noneConfig.fx.enabled && ~noneConfig.space.enabled, ...
    'None FX/space options must disable their modules.');
assert(strcmp(noneConfig.voice.type, 'anonymous'), 'Anonymous mode mapping failed.');

fprintf('test_31_dashboard_config_core passed: shared config mapping is consistent.\n');
