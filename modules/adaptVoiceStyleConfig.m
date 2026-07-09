function [adaptiveConfig, diagnostics] = adaptVoiceStyleConfig(profile, voiceConfig)
%ADAPTVOICESTYLECONFIG Naturalness-priority source-adaptive voice mapping.
%   The planner analyzes the source utterance and chooses the minimum
%   transformation needed to move the voice toward one of four broad voice
%   classes while preserving source prosody and timing.
%
%   Supported style aliases:
%       male / male_deep_gentle
%       female / female_gentle_sweet
%       child / child_bright_soft
%       elder / elder_warm_steady
%
%   Design principles:
%       1) use broad target regions, not one fixed target F0;
%       2) preserve rhythm and F0 contour shape;
%       3) limit pitch-shift magnitude with a smooth saturation rule;
%       4) use only mild, source-dependent envelope/excitation shaping;
%       5) reduce processing when pitch tracking is uncertain or expressive.

if nargin < 2 || isempty(voiceConfig)
    defaults = makeDefaultConfig();
    voiceConfig = defaults.voice;
end

adaptiveConfig = fillVoiceDefaults(voiceConfig);
mode = getVoiceType(adaptiveConfig);
style = canonicalStyle(mode);
prior = stylePrior(style);

intensity = clamp01(getField(adaptiveConfig, 'intensity', 0.72));
params = getField(adaptiveConfig, 'params', struct());
adaptationStrength = clamp01(getField(params, 'adaptationStrength', 0.78));

[prior, targetSource] = applyReferenceProfile(prior, params);

diagnostics = makeDiagnostics(mode, style, prior, targetSource);

if strcmp(style, 'none') || strcmp(style, 'robot_voice')
    diagnostics.reason = 'no_source_adaptation_needed';
    return;
end

if ~isValidProfile(profile)
    diagnostics.usedFallback = true;
    diagnostics.reason = 'invalid_or_unvoiced_profile';
    fallbackFeatures = defaultSourceFeatures();
    adaptiveConfig = applyNaturalStyleParameters( ...
        adaptiveConfig, prior, intensity, 0.50, fallbackFeatures, style);
    adaptiveConfig.pitchShift = fallbackPitch(style, intensity);
    diagnostics.recommendedPitchShift = adaptiveConfig.pitchShift;
    diagnostics.formantScale = adaptiveConfig.params.formantScale;
    diagnostics.envelopeWarpStrength = ...
        adaptiveConfig.params.envelopeWarpStrength;
    return;
end

features = sourceFeatures(profile);
sourceF0 = features.f0Median;
sourceBand = classifyPitchBand(sourceF0);

% Raw distance is measured only to the nearest edge of a broad style band.
% A source already inside the band receives no compulsory pitch movement.
rawShift = distanceToBandSemitones(sourceF0, prior.f0Band);

confidenceFactor = clamp( ...
    0.55 + 0.25*features.voicedRatio + 0.20*features.confidenceMean, ...
    0.65, 1.0);

% Wide pitch range and strong F0 variation are treated as expressive
% prosody. The planner preserves more of that individuality by reducing the
% global shift budget rather than flattening the contour.
rangePenalty = clamp((features.pitchRangeSemitones - 7) / 14, 0, 1);
variationPenalty = clamp((features.f0Cv - 0.14) / 0.30, 0, 1);
prosodyRetention = clamp( ...
    1.0 - 0.14*rangePenalty - 0.10*variationPenalty, 0.78, 1.0);

qualityFactor = (0.90 + 0.10*confidenceFactor) * prosodyRetention;
strengthFactor = 0.80 + 0.20*adaptationStrength;
budgetFactor = qualityFactor * strengthFactor * (0.90 + 0.10*intensity);

if rawShift >= 0
    pitchBudget = prior.maxUpShift * budgetFactor;
else
    pitchBudget = prior.maxDownShift * budgetFactor;
end

recommendedShift = smoothBudgetedShift(rawShift, pitchBudget);

% Naturalness remains the first objective, but every audible voice category
% still needs a source-dependent separation floor. Male/elder floors are
% signed downward and deliberately bounded so they do not become the old
% over-heavy "fat male" failure; female/child floors remain upward.
minimumStyleShift = minimumStyleSeparationShift(style, sourceF0);
floorReliability = clamp( ...
    0.88 + 0.08*confidenceFactor + 0.04*prosodyRetention, 0.88, 1.0);
minimumStyleShift = minimumStyleShift * floorReliability;
styleSeparationApplied = false;
if minimumStyleShift > 0 && recommendedShift < minimumStyleShift
    recommendedShift = minimumStyleShift;
    styleSeparationApplied = true;
elseif minimumStyleShift < 0 && recommendedShift > minimumStyleShift
    recommendedShift = minimumStyleShift;
    styleSeparationApplied = true;
end

% Optional user trim is interpreted as a small artistic correction, not a
% replacement for source-adaptive planning.
manualTrim = getField(adaptiveConfig, 'pitchShift', 0);
if isfiniteScalar(manualTrim) && abs(double(manualTrim)) > 0.01
    recommendedShift = recommendedShift + double(manualTrim);
end
recommendedShift = clamp(recommendedShift, ...
    -1.10*prior.maxDownShift, 1.10*prior.maxUpShift);

outputF0 = sourceF0 * 2^(recommendedShift/12);
residualGap = distanceToBandSemitones(outputF0, prior.f0Band);
mismatch = clamp(abs(rawShift)/12, 0, 1);

adaptiveConfig = applyNaturalStyleParameters( ...
    adaptiveConfig, prior, intensity, mismatch, features, style);
adaptiveConfig.pitchShift = recommendedShift;

adaptiveConfig.params.adaptiveEnabled = true;
adaptiveConfig.params.sourceF0Median = sourceF0;
adaptiveConfig.params.sourcePitchBand = sourceBand;
adaptiveConfig.params.targetF0Band = prior.f0Band;
adaptiveConfig.params.rawPitchDistanceSemitones = rawShift;
adaptiveConfig.params.recommendedOutputF0 = outputF0;
adaptiveConfig.params.targetF0Median = outputF0;
adaptiveConfig.params.residualPitchGapSemitones = residualGap;
adaptiveConfig.params.prosodyRetention = prosodyRetention;
adaptiveConfig.params.pitchBudgetSemitones = pitchBudget;
adaptiveConfig.params.minimumStyleShiftSemitones = minimumStyleShift;
adaptiveConfig.params.styleSeparationApplied = styleSeparationApplied;
adaptiveConfig.params.sourcePitchRangeSemitones = ...
    features.pitchRangeSemitones;
adaptiveConfig.params.sourceDynamicRangeDb = features.dynamicRangeDb;
adaptiveConfig.params.sourceEnergyOnsetRateHz = features.energyOnsetRateHz;
adaptiveConfig.params.sourceRhythmIntervalCv = features.rhythmIntervalCv;
adaptiveConfig.params.sourceSpectralCentroid = features.spectralCentroidMedian;
adaptiveConfig.params.sourceLowBandEnergyRatio = features.lowBandEnergyRatio;
adaptiveConfig.params.sourceHighBandEnergyRatio = features.highBandEnergyRatio;
adaptiveConfig.params.rhythmPolicy = 'preserve_timing_and_pauses';

diagnostics.sourceF0 = sourceF0;
diagnostics.sourcePitchBand = sourceBand;
diagnostics.rawPitchShift = rawShift;
diagnostics.recommendedPitchShift = recommendedShift;
diagnostics.pitchBudgetSemitones = pitchBudget;
diagnostics.minimumStyleShiftSemitones = minimumStyleShift;
diagnostics.styleSeparationApplied = styleSeparationApplied;
diagnostics.recommendedOutputF0 = outputF0;
diagnostics.mappedTargetF0 = outputF0;
diagnostics.residualPitchGapSemitones = residualGap;
diagnostics.prosodyRetention = prosodyRetention;
diagnostics.confidenceFactor = confidenceFactor;
diagnostics.formantScale = adaptiveConfig.params.formantScale;
diagnostics.envelopeWarpStrength = ...
    adaptiveConfig.params.envelopeWarpStrength;
diagnostics.sourcePitchRangeSemitones = features.pitchRangeSemitones;
diagnostics.sourceDynamicRangeDb = features.dynamicRangeDb;
diagnostics.energyOnsetRateHz = features.energyOnsetRateHz;
diagnostics.rhythmIntervalCv = features.rhythmIntervalCv;
diagnostics.reason = 'naturalness_priority_source_adaptation';
end

% -------------------------------------------------------------------------
function shift = smoothBudgetedShift(rawShift, budget)
budget = max(double(budget), 0.05);
if abs(rawShift) < 0.01
    shift = 0;
else
    shift = sign(rawShift) * budget * tanh(abs(rawShift)/budget);
end
end

function semitones = distanceToBandSemitones(f0, band)
f0 = max(double(f0), 1);
low = double(band(1));
high = double(band(2));
if f0 < low
    semitones = 12*log2(low/f0);
elseif f0 > high
    semitones = 12*log2(high/f0);
else
    semitones = 0;
end
end

function minShift = minimumStyleSeparationShift(style, sourceF0)
%MINIMUMSTYLESEPARATIONSHIFT Source-dependent audible category floor.
%   Positive values lift female/child directions. Negative values add a
%   clear but bounded male/elder direction even when the source already sits
%   inside a broad target F0 band.

sourceF0 = clamp(double(sourceF0), 60, 500);
switch canonicalStyle(style)
    case 'male_deep_gentle'
        f0Knots = [60 90 110 130 150 170 190 210 230 260 320 500];
        shiftKnots = [-1.0 -1.3 -1.7 -2.1 -2.4 -2.8 -3.2 -3.7 -4.1 -4.7 -5.2 -5.6];
        minShift = interp1(f0Knots, shiftKnots, sourceF0, 'linear');

    case 'female_gentle_sweet'
        f0Knots = [60 90 110 130 150 170 190 210 230 250 500];
        shiftKnots = [8.0 7.8 7.3 6.3 5.2 4.2 3.2 2.1 0.8 0.0 0.0];
        minShift = interp1(f0Knots, shiftKnots, sourceF0, 'linear');

    case 'child_bright_soft'
        f0Knots = [60 90 110 130 150 180 210 240 270 300 330 380 500];
        shiftKnots = [8.2 8.2 7.8 7.2 6.6 5.6 4.7 3.8 2.8 1.9 1.3 0.8 0.5];
        minShift = interp1(f0Knots, shiftKnots, sourceF0, 'linear');

    case 'elder_warm_steady'
        f0Knots = [60 90 110 130 150 180 210 240 280 340 500];
        shiftKnots = [-0.4 -0.7 -0.9 -1.1 -1.3 -1.6 -1.9 -2.2 -2.6 -3.0 -3.2];
        minShift = interp1(f0Knots, shiftKnots, sourceF0, 'linear');

    otherwise
        minShift = 0;
end
minShift = double(minShift);
end

% -------------------------------------------------------------------------
function config = applyNaturalStyleParameters(config, p, intensity, mismatch, f, style)
% Mild source-dependent spectral/excitation planning.
% Female and child styles receive a bounded source-dependent reinforcement
% only when the source would otherwise remain perceptually too close to the
% original category.
styleStrength = (0.72 + 0.28*intensity);
mismatchFactor = 0.70 + 0.30*clamp01(mismatch);

formantScale = 1 + (p.formantBase - 1) * styleStrength;
formantScale = formantScale + ...
    sign(p.formantBase - 1) * p.formantExtra * mismatch * styleStrength;
formantScale = clamp(formantScale, p.formantMin, p.formantMax);

envelopeStrength = p.envelopeBase * styleStrength * mismatchFactor;
envelopeStrength = clamp(envelopeStrength, 0, p.envelopeMax);

lowGain = p.lowGainBase;
highGain = p.highGainBase;

% Prevent the previous "fat male" failure: low-frequency support is reduced
% when the source is already rich in the low band and added only to thin
% sources.
if isfiniteScalar(f.lowBandEnergyRatio)
    lowError = p.lowRatioReference - double(f.lowBandEnergyRatio);
    lowGain = lowGain + clamp(0.18*lowError, -0.035, 0.035);
end

% Brightness correction is deliberately small. It uses the source spectral
% centroid as a guide, without forcing a fixed target centroid.
if isfiniteScalar(f.spectralCentroidMedian)
    relativeBrightness = log2(max(double(f.spectralCentroidMedian),100) / ...
        max(p.centroidReference,100));
    highGain = highGain - clamp(0.018*relativeBrightness, -0.025, 0.025);
end

% Category reinforcement is deliberately asymmetric. A low-pitched source
% needs more spectral-envelope movement for a convincing female direction;
% a child-like direction needs a higher resonant-envelope placement even
% when the source F0 is already high.
switch canonicalStyle(style)
    case 'male_deep_gentle'
        lowSourceProtection = clamp((125 - f.f0Median)/80, 0, 1);
        formantCeiling = 0.945 + 0.025*lowSourceProtection;
        envelopeFloor = 0.18 - 0.035*lowSourceProtection;
        formantScale = min(formantScale, formantCeiling);
        envelopeStrength = max(envelopeStrength, envelopeFloor);
        lowGain = min(lowGain, 0.004 + 0.010*lowSourceProtection);
        highGain = max(highGain, -0.040);

    case 'female_gentle_sweet'
        lowSourceGap = clamp((205 - f.f0Median)/110, 0, 1);
        formantFloor = 1.045 + 0.055*lowSourceGap;
        envelopeFloor = 0.20 + 0.08*lowSourceGap;
        formantScale = max(formantScale, formantFloor);
        envelopeStrength = max(envelopeStrength, envelopeFloor);
        lowGain = lowGain - 0.018*lowSourceGap;
        highGain = highGain + 0.015*lowSourceGap;

    case 'child_bright_soft'
        youthGap = clamp((330 - f.f0Median)/240, 0, 1);
        formantFloor = 1.075 + 0.040*youthGap;
        envelopeFloor = 0.23 + 0.050*youthGap;
        formantScale = max(formantScale, formantFloor);
        envelopeStrength = max(envelopeStrength, envelopeFloor);
        lowGain = lowGain - (0.008 + 0.012*youthGap);
        highGain = highGain + (0.004 + 0.010*youthGap);

    case 'elder_warm_steady'
        envelopeStrength = max(envelopeStrength, 0.12);
end

formantScale = clamp(formantScale, p.formantMin, p.formantMax);
envelopeStrength = clamp(envelopeStrength, 0, p.envelopeMax);

config.lowGain = clamp(lowGain*styleStrength, -0.08, 0.08);
config.highGain = clamp(highGain*styleStrength, -0.08, 0.08);
config.roughness = clamp(p.roughness*styleStrength, 0, 0.12);

config.params.formantScale = formantScale;
config.params.formantScaleHint = formantScale;
config.params.envelopeWarpStrength = envelopeStrength;
config.params.envelopeWarpMaxGainDb = p.envelopeMaxGainDb;
config.params.envelopeWarpSmoothingTime = p.envelopeSmoothingTime;

config.params.excitationWarmth = clamp(p.warmth*styleStrength, 0, 0.30);
config.params.breathiness = clamp(p.breathiness*styleStrength, 0, 0.12);
config.params.spectralTiltDb = clamp(p.spectralTiltDb*styleStrength, -1.5, 1.5);
config.params.styleRoughness = clamp(p.roughness*styleStrength, 0, 0.12);
config.params.roughnessRateHz = p.roughnessRateHz;

% Preserve natural dynamics. Faster speech receives a somewhat shorter
% release time; slower speech receives a longer release. No time-stretch or
% pause editing is performed.
onsetRate = clamp(f.energyOnsetRateHz, 0.8, 6.0);
releaseScale = clamp(3.0/onsetRate, 0.78, 1.25);
dynamicFactor = clamp((f.dynamicRangeDb - 8)/18, 0, 1);

config.params.compressorThresholdDb = p.compressorThresholdDb;
config.params.compressorRatio = ...
    clamp(p.compressorRatio + 0.12*dynamicFactor, 1.05, 1.65);
config.params.compressorMakeupDb = p.compressorMakeupDb;
config.params.compressorAttackTime = p.compressorAttackTime;
config.params.compressorReleaseTime = ...
    clamp(p.compressorReleaseTime*releaseScale, 0.12, 0.48);

config.params.deEsserThreshold = p.deEsserThreshold;
config.params.deEsserMaxReductionDb = p.deEsserMaxReductionDb;
end

function f = sourceFeatures(profile)
f = defaultSourceFeatures();
f.f0Median = double(profile.f0Median);
f.voicedRatio = safeFeature(profile, 'voicedRatioOfSpeech', ...
    safeFeature(profile, 'voicedRatio', f.voicedRatio));
f.confidenceMean = safeFeature(profile, 'confidenceMean', f.confidenceMean);
f.f0Cv = safeFeature(profile, 'f0Cv', f.f0Cv);
f.pitchRangeSemitones = safeFeature(profile, ...
    'pitchRangeSemitones', f.pitchRangeSemitones);
f.dynamicRangeDb = safeFeature(profile, 'dynamicRangeDb', f.dynamicRangeDb);
f.energyOnsetRateHz = safeFeature(profile, ...
    'energyOnsetRateHz', f.energyOnsetRateHz);
f.rhythmIntervalCv = safeFeature(profile, ...
    'rhythmIntervalCv', f.rhythmIntervalCv);
f.spectralCentroidMedian = safeFeature(profile, ...
    'spectralCentroidMedian', f.spectralCentroidMedian);
f.lowBandEnergyRatio = safeFeature(profile, ...
    'lowBandEnergyRatio', f.lowBandEnergyRatio);
f.highBandEnergyRatio = safeFeature(profile, ...
    'highBandEnergyRatio', f.highBandEnergyRatio);
end

function f = defaultSourceFeatures()
f = struct( ...
    'f0Median', 180, ...
    'voicedRatio', 0.80, ...
    'confidenceMean', 0.80, ...
    'f0Cv', 0.16, ...
    'pitchRangeSemitones', 8.0, ...
    'dynamicRangeDb', 16, ...
    'energyOnsetRateHz', 3.0, ...
    'rhythmIntervalCv', 0.30, ...
    'spectralCentroidMedian', 2000, ...
    'lowBandEnergyRatio', 0.30, ...
    'highBandEnergyRatio', 0.08);
end

function p = stylePrior(style)
% Broad acoustic priors. These are soft engineering regions, not fixed
% physiological definitions and not demographic classifiers.
switch canonicalStyle(style)
    case 'male_deep_gentle'
        p = makePrior([105 195], 5.8, 2.2, ...
            0.955, 0.030, 0.90, 0.98, ...
            0.24, 0.36, 2.8, 0.12, ...
            0.002, -0.024, 2050, 0.29, ...
            0.10, 0.006, -0.35, 0.006, 4.2, ...
            -23, 1.24, 0.12, 0.07, 0.28, ...
            0.54, 2.8);

    case 'female_gentle_sweet'
        p = makePrior([175 300], 2.8, 7.5, ...
            1.055, 0.030, 1.02, 1.13, ...
            0.22, 0.36, 2.8, 0.12, ...
            -0.016, 0.032, 2400, 0.21, ...
            0.02, 0.040, 0.48, 0.003, 4.8, ...
            -24, 1.22, 0.10, 0.06, 0.24, ...
            0.40, 3.4);

    case 'child_bright_soft'
        p = makePrior([260 420], 1.5, 8.2, ...
            1.090, 0.025, 1.05, 1.15, ...
            0.24, 0.34, 2.4, 0.10, ...
            -0.030, 0.030, 2700, 0.16, ...
            0.00, 0.010, 0.45, 0.001, 5.2, ...
            -25, 1.12, 0.02, 0.05, 0.20, ...
            0.30, 5.2);

    case 'elder_warm_steady'
        p = makePrior([100 240], 3.2, 1.8, ...
            0.985, 0.010, 0.95, 1.00, ...
            0.16, 0.28, 2.2, 0.14, ...
            0.008, -0.035, 1850, 0.31, ...
            0.10, 0.055, -0.80, 0.035, 4.4, ...
            -25, 1.32, 0.10, 0.08, 0.34, ...
            0.52, 2.4);

    case 'anonymous'
        p = makePrior([95 155], 4.0, 1.0, ...
            0.96, 0.020, 0.92, 1.00, ...
            0.20, 0.32, 2.5, 0.12, ...
            0.00, -0.04, 1900, 0.29, ...
            0.04, 0.00, -0.50, 0.00, 4.0, ...
            -22, 1.30, 0.10, 0.06, 0.26, ...
            0.50, 2.8);

    otherwise
        p = makePrior([80 420], 0.5, 0.5, ...
            1.0, 0.0, 0.95, 1.05, ...
            0.0, 0.0, 2.0, 0.10, ...
            0, 0, 2100, 0.28, ...
            0, 0, 0, 0, 4.0, ...
            -22, 1.1, 0, 0.06, 0.25, ...
            0.45, 3.0);
end
end

function p = makePrior(f0Band, maxDownShift, maxUpShift, ...
        formantBase, formantExtra, formantMin, formantMax, ...
        envelopeBase, envelopeMax, envelopeMaxGainDb, envelopeSmoothingTime, ...
        lowGainBase, highGainBase, centroidReference, lowRatioReference, ...
        warmth, breathiness, spectralTiltDb, roughness, roughnessRateHz, ...
        compressorThresholdDb, compressorRatio, compressorMakeupDb, ...
        compressorAttackTime, compressorReleaseTime, ...
        deEsserThreshold, deEsserMaxReductionDb)

p = struct( ...
    'f0Band', double(f0Band(:).'), ...
    'maxDownShift', maxDownShift, ...
    'maxUpShift', maxUpShift, ...
    'formantBase', formantBase, ...
    'formantExtra', formantExtra, ...
    'formantMin', formantMin, ...
    'formantMax', formantMax, ...
    'envelopeBase', envelopeBase, ...
    'envelopeMax', envelopeMax, ...
    'envelopeMaxGainDb', envelopeMaxGainDb, ...
    'envelopeSmoothingTime', envelopeSmoothingTime, ...
    'lowGainBase', lowGainBase, ...
    'highGainBase', highGainBase, ...
    'centroidReference', centroidReference, ...
    'lowRatioReference', lowRatioReference, ...
    'warmth', warmth, ...
    'breathiness', breathiness, ...
    'spectralTiltDb', spectralTiltDb, ...
    'roughness', roughness, ...
    'roughnessRateHz', roughnessRateHz, ...
    'compressorThresholdDb', compressorThresholdDb, ...
    'compressorRatio', compressorRatio, ...
    'compressorMakeupDb', compressorMakeupDb, ...
    'compressorAttackTime', compressorAttackTime, ...
    'compressorReleaseTime', compressorReleaseTime, ...
    'deEsserThreshold', deEsserThreshold, ...
    'deEsserMaxReductionDb', deEsserMaxReductionDb);
end

function [p, sourceName] = applyReferenceProfile(p, params)
sourceName = 'style_prior';
if ~isstruct(params) || ~isfield(params, 'targetProfile') || ...
        ~isstruct(params.targetProfile)
    return;
end
target = params.targetProfile;
if isfield(target, 'status') && strcmp(target.status, 'ok') && ...
        isfield(target, 'f0Median') && isfinite(target.f0Median) && ...
        target.f0Median > 0
    center = double(target.f0Median);
    p.f0Band = [0.90*center, 1.10*center];
    sourceName = 'reference_profile';
end
if isfield(target, 'spectralCentroidMedian') && ...
        isfinite(target.spectralCentroidMedian)
    p.centroidReference = double(target.spectralCentroidMedian);
end
if isfield(target, 'lowBandEnergyRatio') && ...
        isfinite(target.lowBandEnergyRatio)
    p.lowRatioReference = clamp( ...
        double(target.lowBandEnergyRatio), 0.05, 0.80);
end
end

function d = makeDiagnostics(mode, style, prior, targetSource)
d = struct( ...
    'mode', mode, ...
    'canonicalStyle', style, ...
    'usedFallback', false, ...
    'reason', '', ...
    'sourceF0', NaN, ...
    'sourcePitchBand', 'unknown', ...
    'targetF0Band', prior.f0Band, ...
    'targetF0', mean(prior.f0Band), ...
    'mappedTargetF0', NaN, ...
    'rawPitchShift', 0, ...
    'recommendedPitchShift', 0, ...
    'pitchBudgetSemitones', 0, ...
    'minimumStyleShiftSemitones', 0, ...
    'styleSeparationApplied', false, ...
    'recommendedOutputF0', NaN, ...
    'residualPitchGapSemitones', 0, ...
    'prosodyRetention', 1, ...
    'confidenceFactor', 1, ...
    'formantScale', 1, ...
    'envelopeWarpStrength', 0, ...
    'sourcePitchRangeSemitones', NaN, ...
    'sourceDynamicRangeDb', NaN, ...
    'energyOnsetRateHz', NaN, ...
    'rhythmIntervalCv', NaN, ...
    'targetSource', targetSource);
end

function shift = fallbackPitch(style, intensity)
strength = 0.75 + 0.25*clamp01(intensity);
switch canonicalStyle(style)
    case 'male_deep_gentle'
        shift = -3.2*strength;
    case 'female_gentle_sweet'
        shift = 2.6*strength;
    case 'child_bright_soft'
        shift = 3.6*strength;
    case 'elder_warm_steady'
        shift = -1.8*strength;
    case 'anonymous'
        shift = -2.5*strength;
    otherwise
        shift = 0;
end
end

function style = canonicalStyle(mode)
mode = lower(strtrim(char(mode)));
switch mode
    case {'male','male_deep_gentle'}
        style = 'male_deep_gentle';
    case {'female','female_gentle_sweet'}
        style = 'female_gentle_sweet';
    case {'child','child_bright_soft'}
        style = 'child_bright_soft';
    case {'elder','elder_warm_steady'}
        style = 'elder_warm_steady';
    case {'robot','robot_voice'}
        style = 'robot_voice';
    case 'anonymous'
        style = 'anonymous';
    otherwise
        style = 'none';
end
end

function band = classifyPitchBand(f0)
if f0 < 110
    band = 'very_low';
elseif f0 < 170
    band = 'low';
elseif f0 < 230
    band = 'mid';
elseif f0 < 290
    band = 'high';
else
    band = 'very_high';
end
end

function tf = isValidProfile(profile)
tf = isstruct(profile) && isfield(profile,'status') && ...
    strcmp(profile.status,'ok') && isfield(profile,'f0Median') && ...
    isfinite(profile.f0Median) && profile.f0Median > 0;
end

function value = safeFeature(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    candidate = s.(name);
    if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        value = double(candidate);
    end
end
end

function config = fillVoiceDefaults(config)
defaults = makeDefaultConfig();
fields = fieldnames(defaults.voice);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config,name)
        config.(name) = defaults.voice.(name);
    end
end
if ~isfield(config,'params') || isempty(config.params)
    config.params = defaults.voice.params;
else
    pFields = fieldnames(defaults.voice.params);
    for k = 1:numel(pFields)
        name = pFields{k};
        if ~isfield(config.params,name)
            config.params.(name) = defaults.voice.params.(name);
        end
    end
end
end

function mode = getVoiceType(config)
if isfield(config,'type') && ~isempty(config.type)
    mode = char(config.type);
elseif isfield(config,'mode') && ~isempty(config.mode)
    mode = char(config.mode);
else
    mode = 'none';
end
end

function value = getField(s, name, defaultValue)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function tf = isfiniteScalar(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value);
end

function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end

function value = clamp01(value)
value = clamp(value, 0, 1);
end
