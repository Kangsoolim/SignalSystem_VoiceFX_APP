%TEST_11_ADAPTIVE_VOICE_CONFIG Validate source-aware parameter mapping.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeDefaultConfig();
voiceConfig = config.voice;
voiceConfig.enabled = true;
voiceConfig.type = 'female';
voiceConfig.intensity = 0.70;
voiceConfig.pitchShift = 0;
voiceConfig.params = struct('adaptationStrength', 0.75);

lowVoice = struct( ...
    'status', 'ok', ...
    'f0Median', 110, ...
    'f0Cv', 0.08, ...
    'voicedRatio', 0.90, ...
    'voicedRatioOfSpeech', 0.92, ...
    'pitchRangeSemitones', 6.5, ...
    'spectralCentroidMedian', 1450, ...
    'energyModulationRateHz', 3.5, ...
    'spectralFlatnessMean', 0.08);

highVoice = lowVoice;
highVoice.f0Median = 185;

[lowCfg, lowDiag] = adaptVoiceStyleConfig(lowVoice, voiceConfig);
[highCfg, highDiag] = adaptVoiceStyleConfig(highVoice, voiceConfig);

assert(lowCfg.pitchShift > highCfg.pitchShift, ...
    'Lower source F0 should receive a larger upward female-style shift.');
assert(lowCfg.pitchShift <= 12.01 && highCfg.pitchShift <= 12.01, ...
    'Pitch recommendations must obey final preset bounds.');
assert(isfield(lowCfg.params, 'adaptiveEnabled') && ...
    lowCfg.params.adaptiveEnabled, 'Adaptive metadata must be present.');
assert(~lowDiag.usedFallback && ~highDiag.usedFallback, ...
    'Valid voiced profiles should not use fallback.');

badProfile = struct('status', 'unvoiced', 'f0Median', NaN);
[fallbackCfg, fallbackDiag] = adaptVoiceStyleConfig(badProfile, voiceConfig);
assert(fallbackDiag.usedFallback, 'Unvoiced profile should use fallback.');
assert(isfinite(fallbackCfg.pitchShift), 'Fallback pitch shift must be finite.');

disp('test_11_adaptive_voice_config passed: source-aware mapping works.');
disp(lowDiag);
disp(highDiag);
