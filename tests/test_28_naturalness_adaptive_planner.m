%TEST_28_NATURALNESS_ADAPTIVE_PLANNER Validate feature-aware processing budget.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

base = makeProfile();
expressive = base;
expressive.pitchRangeSemitones = 18;
expressive.f0Cv = 0.34;

fast = base;
fast.energyOnsetRateHz = 5.2;

slow = base;
slow.energyOnsetRateHz = 1.4;

defaults = makeDefaultConfig();
v = defaults.voice;
v.enabled = true;
v.type = 'male_deep_gentle';
v.mode = 'male_deep_gentle';
v.intensity = 0.70;

[stableCfg,stableDiag] = adaptVoiceStyleConfig(base,v);
[expressiveCfg,expressiveDiag] = adaptVoiceStyleConfig(expressive,v);
[fastCfg,fastDiag] = adaptVoiceStyleConfig(fast,v);
[slowCfg,slowDiag] = adaptVoiceStyleConfig(slow,v);

assert(abs(expressiveCfg.pitchShift) < abs(stableCfg.pitchShift), ...
    'Expressive source should receive a smaller global pitch shift.');
assert(expressiveDiag.prosodyRetention < stableDiag.prosodyRetention, ...
    'Wide expressive prosody should increase preservation priority.');
assert(fastCfg.params.compressorReleaseTime < ...
    slowCfg.params.compressorReleaseTime, ...
    'Faster speech should receive a shorter release time.');
assert(strcmp(stableCfg.params.rhythmPolicy,'preserve_timing_and_pauses'), ...
    'Planner must preserve timing and pauses rather than time-stretch speech.');
assert(isfinite(fastDiag.energyOnsetRateHz) && ...
    isfinite(slowDiag.energyOnsetRateHz), ...
    'Rhythm proxy diagnostics must be exposed.');

disp('test_28_naturalness_adaptive_planner passed: pitch, prosody, rhythm and dynamics influence the plan.');

function p = makeProfile()
p = struct();
p.status = 'ok';
p.f0Median = 305.8911;
p.voicedRatioOfSpeech = 0.88;
p.voicedRatio = 0.82;
p.confidenceMean = 0.90;
p.f0Cv = 0.14;
p.pitchRangeSemitones = 7.5;
p.spectralCentroidMedian = 2350;
p.lowBandEnergyRatio = 0.24;
p.highBandEnergyRatio = 0.09;
p.dynamicRangeDb = 18;
p.energyOnsetRateHz = 3.0;
p.rhythmIntervalCv = 0.28;
end
