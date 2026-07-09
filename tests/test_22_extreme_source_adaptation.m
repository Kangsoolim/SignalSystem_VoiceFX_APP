%TEST_22_EXTREME_SOURCE_ADAPTATION Validate natural mapping over wide F0 range.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

styles = {'male_deep_gentle','female_gentle_sweet', ...
    'child_bright_soft','elder_warm_steady'};
sourceF0Values = [90,120,160,210,305,340,392];

configs = cell(numel(styles),numel(sourceF0Values));
diags = cell(size(configs));

for s = 1:numel(styles)
    for k = 1:numel(sourceF0Values)
        profile = syntheticProfile(sourceF0Values(k));
        defaults = makeDefaultConfig();
        v = defaults.voice;
        v.enabled = true;
        v.type = styles{s};
        v.mode = styles{s};
        v.intensity = 0.70;

        [adapted,diag] = adaptVoiceStyleConfig(profile,v);
        configs{s,k} = adapted;
        diags{s,k} = diag;

        assert(isfinite(adapted.pitchShift), 'Pitch shift must be finite.');
        assert(isfinite(adapted.params.formantScale), ...
            'Formant scale must be finite.');
        assert(adapted.params.formantScale >= 0.90 && ...
            adapted.params.formantScale <= 1.20, ...
            'Natural formant scale must stay in a mild safe range.');
        assert(adapted.params.envelopeWarpStrength >= 0 && ...
            adapted.params.envelopeWarpStrength <= 0.5, ...
            'Natural envelope strength must stay mild.');
        assert(diag.prosodyRetention >= 0.78 && ...
            diag.prosodyRetention <= 1.001, ...
            'Prosody retention must stay in the designed range.');
        assert(numel(diag.targetF0Band) == 2, ...
            'Diagnostics must expose a broad target F0 band.');
        assert(isfinite(diag.recommendedOutputF0), ...
            'Planned output F0 must be finite.');
    end
end

% Male: progressively higher sources receive progressively stronger downward
% correction, but the planner never uses the old extreme hard placement.
maleHigh = configs{1,5}.pitchShift;
maleVeryHigh = configs{1,7}.pitchShift;
assert(maleHigh < -3.5 && maleHigh > -5.9, ...
    '305 Hz source -> male should use moderate bounded downward shift.');
assert(maleVeryHigh <= maleHigh, ...
    'Higher source should not receive a weaker male-direction correction.');

% Female: low sources move upward; very high sources receive only moderate
% downward correction. One fixed preset would fail this ordering.
assert(configs{2,2}.pitchShift > 3.0, ...
    '120 Hz source -> female should move upward.');
assert(configs{2,7}.pitchShift < 0 && ...
    configs{2,7}.pitchShift > -3.2, ...
    'Very-high source -> female correction should be moderate and downward.');

% Child: low sources need substantial upward help. Already-high adult
% sources still receive a small positive lift plus a stronger upward
% envelope direction so the result does not collapse to ordinary female.
assert(configs{3,2}.pitchShift > 7.5, ...
    'Low source -> child should receive substantial but bounded upward shift.');
assert(configs{3,5}.pitchShift > 1.5 && ...
    configs{3,5}.pitchShift < 4.0, ...
    '305 Hz source -> child should receive a small but audible positive lift.');
assert(configs{3,5}.params.formantScale > ...
    configs{2,5}.params.formantScale, ...
    'Child mapping should use a stronger upward envelope direction than female.');

% Elder: age direction is intentionally mild and source-dependent.
assert(abs(configs{4,3}.pitchShift) < 0.2, ...
    '160 Hz source already in elder region should preserve pitch.');
assert(configs{4,5}.pitchShift < -1.5 && ...
    configs{4,5}.pitchShift > -3.6, ...
    'High source -> elder should lower moderately, not aggressively.');

disp('test_22_extreme_source_adaptation passed: natural mapping is bounded and source-dependent.');

function profile = syntheticProfile(f0)
profile = struct();
profile.status = 'ok';
profile.f0Median = f0;
profile.voicedRatioOfSpeech = 0.84;
profile.voicedRatio = 0.84;
profile.confidenceMean = 0.90;
profile.f0Cv = 0.14;
profile.pitchRangeSemitones = 8.0;
profile.spectralCentroidMedian = 1900 + 1.5*(f0-170);
profile.lowBandEnergyRatio = min(max(0.40 - 0.0005*(f0-170),0.18),0.55);
profile.highBandEnergyRatio = min(max(0.06 + 0.00015*(f0-170),0.02),0.13);
profile.dynamicRangeDb = 18;
profile.energyOnsetRateHz = 3.0;
profile.rhythmIntervalCv = 0.30;
end
