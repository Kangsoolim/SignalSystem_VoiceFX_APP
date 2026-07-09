%TEST_29_CHILD_FEMALE_CATEGORY_SEPARATION
% Validate the last targeted tuning:
%   1) low-pitched sources obtain a clearly audible female-direction lift;
%   2) child style remains distinguishable from female for low and high
%      sources without forcing one fixed output F0;
%   3) male and elder planners are not modified by the category floor.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

defaults = makeDefaultConfig();

lowSource = makeProfile(130);
highSource = makeProfile(305.8911);

female = defaults.voice;
female.enabled = true;
female.type = 'female_gentle_sweet';
female.mode = 'female_gentle_sweet';
female.intensity = 0.70;

child = defaults.voice;
child.enabled = true;
child.type = 'child_bright_soft';
child.mode = 'child_bright_soft';
child.intensity = 0.70;

male = defaults.voice;
male.enabled = true;
male.type = 'male_deep_gentle';
male.mode = 'male_deep_gentle';
male.intensity = 0.70;

elder = defaults.voice;
elder.enabled = true;
elder.type = 'elder_warm_steady';
elder.mode = 'elder_warm_steady';
elder.intensity = 0.70;

[lowFemaleCfg, lowFemaleDiag] = adaptVoiceStyleConfig(lowSource, female);
[lowChildCfg, lowChildDiag] = adaptVoiceStyleConfig(lowSource, child);
[highFemaleCfg, highFemaleDiag] = adaptVoiceStyleConfig(highSource, female);
[highChildCfg, highChildDiag] = adaptVoiceStyleConfig(highSource, child);
[highMaleCfg, highMaleDiag] = adaptVoiceStyleConfig(highSource, male);
[highElderCfg, highElderDiag] = adaptVoiceStyleConfig(highSource, elder);

assert(lowFemaleCfg.pitchShift > 5.5 && lowFemaleCfg.pitchShift < 8.3, ...
    '130 Hz source -> female needs a clear but bounded upward shift.');
assert(lowFemaleCfg.params.formantScale >= 1.075 && ...
    lowFemaleCfg.params.formantScale <= 1.13, ...
    'Low source -> female needs a bounded upward envelope direction.');
assert(lowFemaleCfg.params.envelopeWarpStrength >= 0.23 && ...
    lowFemaleCfg.params.envelopeWarpStrength <= 0.36, ...
    'Low source -> female envelope change should be audible but bounded.');
assert(lowFemaleDiag.styleSeparationApplied, ...
    'Low source -> female should activate minimum category separation.');

assert(lowChildCfg.pitchShift > lowFemaleCfg.pitchShift + 1.5, ...
    'Low source -> child must move higher than female.');
assert(lowChildCfg.pitchShift > 8.0 && lowChildCfg.pitchShift <= 10.5, ...
    '130 Hz source -> child should receive a strong but bounded lift.');
assert(lowChildCfg.params.formantScale >= 1.14 && ...
    lowChildCfg.params.formantScale <= 1.20, ...
    'Low source -> child needs a clearly higher envelope direction.');
assert(lowChildCfg.params.envelopeWarpStrength >= 0.33 && ...
    lowChildCfg.params.envelopeWarpStrength <= 0.45, ...
    'Low source -> child envelope change should be stronger than female.');

assert(highChildCfg.pitchShift > 1.5 && highChildCfg.pitchShift < 4.0, ...
    'High adult source -> child still needs a small audible pitch lift.');
assert(highChildCfg.params.formantScale >= 1.10 && ...
    highChildCfg.params.formantScale <= 1.20, ...
    'High adult source -> child needs upward formant direction.');
assert(highChildCfg.params.envelopeWarpStrength >= 0.29, ...
    'High adult source -> child needs minimum youthful envelope shaping.');
assert(highChildCfg.params.formantScale > ...
    highFemaleCfg.params.formantScale, ...
    'Child formant direction must remain stronger than female.');

assert(highFemaleCfg.pitchShift <= 0.2, ...
    'Already-high source -> female should remain close to its natural pitch.');
assert(~highMaleDiag.styleSeparationApplied && ...
    ~highElderDiag.styleSeparationApplied, ...
    'Targeted category floor must not affect male or elder planners.');
assert(highMaleCfg.pitchShift < 0 && highElderCfg.pitchShift < 0, ...
    'High source male/elder directions should remain downward.');

% Source individuality is preserved: two child outputs do not collapse to a
% single F0 even though both move in the child direction.
assert(abs(lowChildDiag.recommendedOutputF0 - ...
    highChildDiag.recommendedOutputF0) > 40, ...
    'Child planner must not collapse different sources to one fixed F0.');

disp('test_29_child_female_category_separation passed.');

function p = makeProfile(f0)
p = struct();
p.status = 'ok';
p.f0Median = f0;
p.voicedRatioOfSpeech = 0.86;
p.voicedRatio = 0.84;
p.confidenceMean = 0.91;
p.f0Cv = 0.15;
p.pitchRangeSemitones = 8.5;
p.spectralCentroidMedian = 1750 + 1.6*(f0-150);
p.lowBandEnergyRatio = min(max(0.42 - 0.00055*(f0-150),0.18),0.56);
p.highBandEnergyRatio = min(max(0.05 + 0.00018*(f0-150),0.02),0.14);
p.dynamicRangeDb = 19;
p.energyOnsetRateHz = 3.1;
p.rhythmIntervalCv = 0.29;
end
