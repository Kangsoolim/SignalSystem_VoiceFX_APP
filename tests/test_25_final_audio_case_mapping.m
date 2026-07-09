%TEST_25_FINAL_AUDIO_CASE_MAPPING Natural mapping for observed source cases.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

sourceF0 = [120,210,290,305.8911,339,392];
styles = {'male_deep_gentle','female_gentle_sweet', ...
    'child_bright_soft','elder_warm_steady'};

shiftTable = zeros(numel(sourceF0),numel(styles));
formantTable = zeros(size(shiftTable));
outputF0Table = zeros(size(shiftTable));

for i = 1:numel(sourceF0)
    profile = makeProfile(sourceF0(i));
    for j = 1:numel(styles)
        defaults = makeDefaultConfig();
        v = defaults.voice;
        v.enabled = true;
        v.type = styles{j};
        v.mode = styles{j};
        v.intensity = 0.70;

        [cfg,diag] = adaptVoiceStyleConfig(profile,v);
        shiftTable(i,j) = cfg.pitchShift;
        formantTable(i,j) = cfg.params.formantScale;
        outputF0Table(i,j) = diag.recommendedOutputF0;

        assert(isfinite(diag.recommendedOutputF0), ...
            'Planned output F0 must be finite.');
        assert(diag.prosodyRetention >= 0.78, ...
            'Planner must preserve expressive prosody.');
    end
end

% User-observed high source around 305.8911 Hz.
row = 4;
assert(shiftTable(row,1) < -3.5 && shiftTable(row,1) > -5.9, ...
    'Observed high source male mapping should be moderate, not extreme.');
assert(shiftTable(row,2) <= 0 && shiftTable(row,2) > -2.0, ...
    'Observed high source female mapping should be nearly preserved.');
assert(shiftTable(row,3) > 1.5 && shiftTable(row,3) < 4.0, ...
    'Observed high source child mapping should add a small audible lift.');
assert(shiftTable(row,4) < -1.5 && shiftTable(row,4) > -3.6, ...
    'Observed high source elder mapping should lower gently.');

assert(formantTable(row,1) < 1.0 && formantTable(row,1) > 0.90, ...
    'Male envelope shift must be downward but mild.');
assert(formantTable(row,2) > 1.0 && formantTable(row,2) < 1.11, ...
    'Female envelope shift must be upward but mild.');
assert(formantTable(row,3) > formantTable(row,2) && ...
    formantTable(row,3) <= 1.20, ...
    'Child envelope direction should exceed female without over-warping.');
assert(formantTable(row,4) <= 1.0 && formantTable(row,4) >= 0.95, ...
    'Elder envelope shift must remain subtle.');

% Source adaptation: outputs are not collapsed to one fixed target F0.
assert(abs(outputF0Table(1,2)-outputF0Table(end,2)) > 15, ...
    'Female planner should preserve source individuality instead of one fixed F0.');
assert(abs(outputF0Table(1,3)-outputF0Table(end,3)) > 15, ...
    'Child planner should preserve source individuality instead of one fixed F0.');

disp('test_25_final_audio_case_mapping passed: observed cases use natural source-adaptive plans.');

function p = makeProfile(f0)
p = struct();
p.status = 'ok';
p.f0Median = f0;
p.voicedRatioOfSpeech = 0.84;
p.voicedRatio = 0.84;
p.confidenceMean = 0.90;
p.f0Cv = 0.15;
p.pitchRangeSemitones = 8.5;
p.spectralCentroidMedian = 1800 + 1.5*(f0-170);
p.lowBandEnergyRatio = min(max(0.40 - 0.0005*(f0-170),0.18),0.55);
p.highBandEnergyRatio = min(max(0.05 + 0.00018*(f0-170),0.02),0.13);
p.dynamicRangeDb = 20;
p.energyOnsetRateHz = 3.0;
p.rhythmIntervalCv = 0.30;
end
