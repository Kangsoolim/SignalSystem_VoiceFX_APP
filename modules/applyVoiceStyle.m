function [yFrame, state] = applyVoiceStyle(xFrame, fs, voiceConfig, state)
%APPLYVOICESTYLE Source-aware, stateful DSP voice-style transformation.
%   [yFrame, state] = applyVoiceStyle(xFrame, fs, voiceConfig, state)
%
%   Design goals:
%   1. preserve the public frame/state interface used by the whole project;
%   2. never restart pitch history at frame boundaries;
%   3. keep source prosody while shifting the median pitch region;
%   4. separate pitch placement from conservative timbre shaping;
%   5. bypass/soften the effect during silence to avoid shifting noise;
%   6. keep every internal control bounded and temporally smoothed.
%
%   This module is a robust DSP baseline. It is not neural speaker cloning.

if nargin < 3 || isempty(voiceConfig)
    voiceConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
voiceConfig = fillVoiceDefaults(voiceConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'voice') || isempty(state.voice)
    state.voice = struct();
end

x = cleanColumn(xFrame);
yFrame = x;
if isempty(x) || ~voiceConfig.enabled
    return;
end

voiceType = getVoiceType(voiceConfig);
voiceFamily = styleFamily(voiceType);
if strcmpi(voiceFamily, 'none')
    return;
end
if isempty(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('applyVoiceStyle:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

state = initializeVoiceState(state, voiceType, fs, voiceConfig);
dry = x;

[effectiveConfig, state] = resolveAdaptiveVoiceConfig( ...
    dry, fs, voiceConfig, state, voiceType);

intensity = clamp01(getField(effectiveConfig, 'intensity', 0.6));
userMix = clamp01(getField(effectiveConfig, 'mix', 1.0));

% Smooth the target semitone offset across frames. A sudden parameter jump is
% one of the most audible failure modes in realtime voice effects.
targetSemitones = stylePitchTarget(effectiveConfig, voiceType, intensity);
[state, semitones] = smoothPitchTarget(state, targetSemitones, ...
    numel(dry), fs, effectiveConfig);

% Always advance the pitch shifter state, even when the output gate is near
% zero. This keeps delay/phase history coherent when speech resumes.
switch lower(voiceFamily)
    case 'robot_voice'
        wet = robotVoice(dry, fs, effectiveConfig, state);

    otherwise
        [wet, state] = statefulDualDelayPitchShift( ...
            dry, fs, semitones, effectiveConfig, state);

        [wet, state] = timbreShapeAdaptive( ...
            wet, fs, effectiveConfig, state, voiceFamily, intensity);

        % First-round V2.5 upgrade: broad envelope placement, source-like
        % excitation shaping and bounded style dynamics are independent from
        % pitch placement. This makes the four styles differ in more than F0.
        [wet, state] = warpSpectralEnvelope( ...
            wet, fs, effectiveConfig, state);
        [wet, state] = shapeVoiceExcitation( ...
            wet, fs, effectiveConfig, state);
        [wet, state] = applyStyleDynamics( ...
            wet, fs, effectiveConfig, state);

        if logical(getParam(effectiveConfig, 'deEsserEnabled', true)) && ...
                any(strcmpi(voiceFamily, {'female', 'child'}))
            [wet, state] = gentleDeEsser(wet, fs, effectiveConfig, state);
        end

        if strcmpi(voiceFamily, 'anonymous')
            [wet, state] = speechBandShape(wet, fs, state, 150, 5200);
        end
end

[wet, state] = smoothedRmsMatch(wet, dry, state, 2.0);
wet = softLimitLocal(wet, 1.05);

% Speech-aware output gate: keep background noise from being aggressively
% pitch shifted, but use slow attack/release to avoid chopping word onsets.
[state, speechGate] = updateSpeechGate(state, dry, fs, effectiveConfig);
[state, wetRamp] = updateWetRamp(state, numel(dry), fs, voiceType, effectiveConfig);

modeMixScale = styleMixScale(voiceFamily);
effectiveMix = userMix * modeMixScale .* wetRamp .* speechGate;
yFrame = (1 - effectiveMix) .* dry + effectiveMix .* wet;

yFrame = cleanColumn(yFrame);
yFrame = min(max(yFrame, -1), 1);

state.voice.sampleIndex = state.voice.sampleIndex + numel(yFrame);
state.voice.lastMode = voiceType;
state.voice.lastFs = fs;
state.voice.lastSemitones = semitones;
state.voice.lastSpeechGate = speechGate(end);
end

% =========================================================================
% Calibration and source-aware mapping
% =========================================================================
function [effectiveConfig, state] = resolveAdaptiveVoiceConfig( ...
        x, fs, voiceConfig, state, voiceType)

effectiveConfig = voiceConfig;
params = getField(voiceConfig, 'params', struct());
adaptiveEnabled = logical(getField(params, 'adaptiveEnabled', true));

if ~adaptiveEnabled || strcmpi(voiceType, 'robot_voice')
    state.voice.calibrationStatus = 'disabled';
    state.voice.adaptiveConfig = effectiveConfig;
    return;
end

calibrationSeconds = clamp(double(getField(params, ...
    'calibrationSeconds', 0.80)), 0.25, 5.0);
requiredSamples = max(256, round(calibrationSeconds * fs));
profile = [];

if isfield(params, 'sourceProfile') && isstruct(params.sourceProfile) && ...
        ~isempty(fieldnames(params.sourceProfile))
    profile = params.sourceProfile;
    state.voice.sourceProfile = profile;
    state.voice.calibrationStatus = 'ready_external';
elseif isfield(state.voice, 'sourceProfile') && ...
        isValidVoiceProfile(state.voice.sourceProfile)
    profile = state.voice.sourceProfile;
    state.voice.calibrationStatus = 'ready';
end

if isempty(profile)
    if ~isfield(state.voice, 'calibrationBuffer') || ...
            isempty(state.voice.calibrationBuffer)
        state.voice.calibrationBuffer = zeros(0, 1);
    end

    remaining = requiredSamples - numel(state.voice.calibrationBuffer);
    if remaining > 0
        takeCount = min(remaining, numel(x));
        if takeCount > 0
            state.voice.calibrationBuffer = [state.voice.calibrationBuffer; ...
                x(1:takeCount)]; %#ok<AGROW>
        end
    end

    state.voice.calibrationSamples = numel(state.voice.calibrationBuffer);
    state.voice.calibrationRequiredSamples = requiredSamples;

    if numel(state.voice.calibrationBuffer) >= requiredSamples
        profileOptions = getField(params, 'profileOptions', struct());
        profile = analyzeVoiceProfile( ...
            state.voice.calibrationBuffer, fs, profileOptions);
        if isValidVoiceProfile(profile)
            state.voice.sourceProfile = profile;
            state.voice.calibrationStatus = 'ready';
        else
            state.voice.calibrationStatus = 'retry_unvoiced';
            profile = [];
            % Keep only a short tail and continue collecting. A user may
            % start the realtime session with silence; a failed first window
            % must not permanently lock the engine to a silent calibration.
            keepCount = min(numel(state.voice.calibrationBuffer), ...
                round(0.25 * requiredSamples));
            if keepCount > 0
                state.voice.calibrationBuffer = ...
                    state.voice.calibrationBuffer(end-keepCount+1:end);
            else
                state.voice.calibrationBuffer = zeros(0, 1);
            end
        end
    else
        state.voice.calibrationStatus = 'collecting';
    end
end

if ~isempty(profile) && isValidVoiceProfile(profile)
    [effectiveConfig, diagnostics] = ...
        adaptVoiceStyleConfig(profile, voiceConfig);
    state.voice.adaptiveConfig = effectiveConfig;
    state.voice.adaptiveDiagnostics = diagnostics;
    state.voice.lastAdaptiveMode = voiceType;
else
    % Use the mapper's bounded fallback instead of an unbounded raw preset.
    fallbackProfile = struct('status', 'unvoiced', 'f0Median', NaN);
    [effectiveConfig, diagnostics] = ...
        adaptVoiceStyleConfig(fallbackProfile, voiceConfig);
    state.voice.adaptiveConfig = effectiveConfig;
    state.voice.adaptiveDiagnostics = diagnostics;
end
end

function tf = isValidVoiceProfile(profile)
tf = isstruct(profile) && isfield(profile, 'status') && ...
    strcmp(profile.status, 'ok') && isfield(profile, 'f0Median') && ...
    isfinite(profile.f0Median) && profile.f0Median > 0;
end

% =========================================================================
% State initialization and parameter smoothing
% =========================================================================
function state = initializeVoiceState(state, voiceType, fs, config)
if ~isfield(state.voice, 'sampleIndex'), state.voice.sampleIndex = 0; end
if ~isfield(state.voice, 'calibrationStatus')
    state.voice.calibrationStatus = 'not_started';
end
if ~isfield(state.voice, 'wetRampValue'), state.voice.wetRampValue = 0; end
if ~isfield(state.voice, 'speechGateValue'), state.voice.speechGateValue = 0; end
if ~isfield(state.voice, 'rmsGain'), state.voice.rmsGain = 1; end
if ~isfield(state.voice, 'currentPitchSemitones')
    state.voice.currentPitchSemitones = NaN;
end

styleChanged = ~isfield(state.voice, 'styleSignature') || ...
    ~strcmp(state.voice.styleSignature, voiceType);
fsChanged = isfield(state.voice, 'lastFs') && ...
    ~isempty(state.voice.lastFs) && state.voice.lastFs ~= fs;

if styleChanged || fsChanged
    state.voice.styleSignature = voiceType;
    state.voice.wetRampValue = 0;
    state.voice.rmsGain = 1;
    state.voice.deEsserGain = 1;
    state.voice.timbrePrev = zeros(3, 1);
    state.voice.bandPrev = zeros(2, 1);
    state.voice.currentPitchSemitones = NaN;
    state = resetPitchState(state, fs, config);

    if fsChanged
        state.voice.calibrationBuffer = zeros(0, 1);
        state.voice.calibrationSamples = 0;
        state.voice.calibrationStatus = 'not_started';
        if isfield(state.voice, 'sourceProfile')
            state.voice = rmfield(state.voice, 'sourceProfile');
        end
    end
elseif ~isfield(state.voice, 'pitchBuffer')
    state = resetPitchState(state, fs, config);
end
end

function [state, semitones] = smoothPitchTarget(state, target, frameLength, fs, config)
timeConstant = max(0.01, double(getParam(config, ...
    'pitchSmoothingTime', 0.10)));
alpha = exp(-(frameLength / fs) / timeConstant);
current = state.voice.currentPitchSemitones;
if ~isfinite(current)
    semitones = double(target);
else
    semitones = alpha * current + (1 - alpha) * double(target);
end
state.voice.currentPitchSemitones = semitones;
end

function target = stylePitchTarget(config, voiceType, intensity)
voiceType = styleFamily(voiceType);
manual = getField(config, 'pitchShift', 0);
if isfinite(double(manual)) && abs(double(manual)) > 0.01
    target = double(manual);
    return;
end

switch lower(voiceType)
    case 'male'
        target = -2.2 * (0.45 + 0.55 * intensity);
    case 'female'
        target = 2.8 * (0.45 + 0.55 * intensity);
    case 'child'
        target = 4.2 * (0.45 + 0.55 * intensity);
    case 'elder'
        target = -1.4 * (0.45 + 0.55 * intensity);
    case 'anonymous'
        target = -3.5 * (0.45 + 0.55 * intensity);
    otherwise
        target = 0;
end
end

function scale = styleMixScale(voiceType)
voiceType = styleFamily(voiceType);
% Curated V2.5 styles use the full transformed signal. Source preservation is
% handled inside pitch/envelope/excitation mapping; blending dry source back
% into cross-category conversion can leak the original voice identity.
if any(strcmpi(voiceType, {'male', 'female', 'child', 'elder'}))
    scale = 1.0;
else
    scale = 1.0;
end
end

% =========================================================================
% Stateful dual-delay pitch shifter
% =========================================================================
function state = resetPitchState(state, fs, config)
maxDelayMs = clamp(double(getParam(config, ...
    'pitchMaxDelayMs', 35)), 20, 65);
D = max(32, round(maxDelayMs * 1e-3 * fs));
state.voice.pitchBuffer = zeros(D + 8, 1);
state.voice.pitchWriteIndex = 1;
state.voice.pitchPhase = 0.25;
state.voice.pitchMaxDelaySamples = D;
state.voice.pitchFs = fs;
state.voice.pitchBufferPrimed = false;
end

function [y, state] = statefulDualDelayPitchShift(x, fs, semitones, config, state)
%STATEFULDUALDELAYPITCHSHIFT Continuous realtime-safe pitch shift.
%   Two complementary variable-delay branches are crossfaded. Buffer, phase
%   and write index persist in state.voice, so frame boundaries do not reset
%   the delay trajectory.

x = cleanColumn(x);
if isempty(x)
    y = x;
    return;
end

if ~isfield(state.voice, 'pitchBuffer') || ...
        ~isfield(state.voice, 'pitchFs') || state.voice.pitchFs ~= fs
    state = resetPitchState(state, fs, config);
end
if ~isfield(state.voice, 'pitchBufferPrimed') || ...
        ~state.voice.pitchBufferPrimed
    state.voice.pitchBuffer(:) = x(1);
    state.voice.pitchBufferPrimed = true;
end

if abs(semitones) < 0.02
    % Still write input into history so a later parameter change starts from
    % current audio rather than an all-zero delay buffer.
    [~, state] = writePitchHistoryOnly(x, state);
    y = x;
    return;
end

pitchFactor = 2 ^ (double(semitones) / 12);
D = double(state.voice.pitchMaxDelaySamples);
phaseIncrement = abs(pitchFactor - 1) / max(D, 1);
phaseIncrement = min(phaseIncrement, 0.02);

buffer = state.voice.pitchBuffer;
N = numel(buffer);
writeIndex = state.voice.pitchWriteIndex;
phase = state.voice.pitchPhase;
y = zeros(size(x));

for n = 1:numel(x)
    buffer(writeIndex) = x(n);

    p1 = phase;
    p2 = mod(phase + 0.5, 1.0);
    if pitchFactor >= 1
        d1 = D * (1 - p1);
        d2 = D * (1 - p2);
    else
        d1 = D * p1;
        d2 = D * p2;
    end

    s1 = readCubicCircular(buffer, writeIndex, d1);
    s2 = readCubicCircular(buffer, writeIndex, d2);

    % Complementary Hann amplitudes sum to one.
    g1 = sin(pi * p1) ^ 2;
    g2 = sin(pi * p2) ^ 2;
    y(n) = g1 * s1 + g2 * s2;

    writeIndex = writeIndex + 1;
    if writeIndex > N, writeIndex = 1; end
    phase = phase + phaseIncrement;
    phase = phase - floor(phase);
end

state.voice.pitchBuffer = buffer;
state.voice.pitchWriteIndex = writeIndex;
state.voice.pitchPhase = phase;
end

function [y, state] = writePitchHistoryOnly(x, state)
buffer = state.voice.pitchBuffer;
N = numel(buffer);
writeIndex = state.voice.pitchWriteIndex;
for n = 1:numel(x)
    buffer(writeIndex) = x(n);
    writeIndex = writeIndex + 1;
    if writeIndex > N, writeIndex = 1; end
end
state.voice.pitchBuffer = buffer;
state.voice.pitchWriteIndex = writeIndex;
y = x;
end

function sample = readCubicCircular(buffer, writeIndex, delaySamples)
%READCUBICCIRCULAR Catmull-Rom interpolation with safe 1-based indexing.
N = numel(buffer);
rawPosition = double(writeIndex) - double(delaySamples);
pos0 = mod(rawPosition - 1, N); % zero-based position in [0,N)
base0 = floor(pos0);
mu = pos0 - base0;

im1 = mod(base0 - 1, N) + 1;
i0  = mod(base0,     N) + 1;
i1  = mod(base0 + 1, N) + 1;
i2  = mod(base0 + 2, N) + 1;

ym1 = buffer(im1);
y0 = buffer(i0);
y1 = buffer(i1);
y2 = buffer(i2);

sample = 0.5 * ((2 * y0) + ...
    (-ym1 + y1) * mu + ...
    (2 * ym1 - 5 * y0 + 4 * y1 - y2) * mu ^ 2 + ...
    (-ym1 + 3 * y0 - 3 * y1 + y2) * mu ^ 3);
end

% =========================================================================
% Timbre shaping, de-essing and dynamics
% =========================================================================
function [y, state] = timbreShapeAdaptive(x, fs, config, state, voiceType, intensity)
if ~isfield(state.voice, 'timbrePrev') || numel(state.voice.timbrePrev) ~= 3
    state.voice.timbrePrev = zeros(3, 1);
end
prev = state.voice.timbrePrev;

[low, prev(1)] = onePoleLowpass(x, fs, 300, prev(1));
[belowBody, prev(2)] = onePoleLowpass(x, fs, 1300, prev(2));
[belowPresence, prev(3)] = onePoleLowpass(x, fs, ...
    min(3800, 0.40 * fs), prev(3));

body = belowBody - low;
presence = belowPresence - belowBody;
air = x - belowPresence;

lowGain = clamp(double(getField(config, 'lowGain', 0)), -0.35, 0.35);
highGain = clamp(double(getField(config, 'highGain', 0)), -0.30, 0.30);

switch lower(voiceType)
    case 'male'
        bodyGain = 0.10 * intensity;
        presenceGain = -0.03 * intensity;
    case 'female'
        bodyGain = -0.04 * intensity;
        presenceGain = 0.08 * intensity;
    case 'child'
        bodyGain = -0.07 * intensity;
        presenceGain = 0.10 * intensity;
    case 'elder'
        bodyGain = 0.05 * intensity;
        presenceGain = -0.06 * intensity;
    otherwise
        bodyGain = 0;
        presenceGain = 0;
end

y = x + lowGain * low + bodyGain * body + ...
    presenceGain * presence + highGain * air;
state.voice.timbrePrev = prev;
end

function [y, state] = gentleDeEsser(x, fs, config, state)
cutoff = min(5200, 0.40 * fs);
if cutoff <= 1000
    y = x;
    return;
end
if ~isfield(state.voice, 'deEsserLpPrev')
    state.voice.deEsserLpPrev = 0;
end
if ~isfield(state.voice, 'deEsserGain') || ~isfinite(state.voice.deEsserGain)
    state.voice.deEsserGain = 1;
end

[lowPart, state.voice.deEsserLpPrev] = onePoleLowpass( ...
    x, fs, cutoff, state.voice.deEsserLpPrev);
highPart = x - lowPart;

highRms = sqrt(mean(highPart .^ 2));
totalRms = sqrt(mean(x .^ 2)) + eps;
ratio = highRms / totalRms;
threshold = clamp(double(getParam(config, ...
    'deEsserThreshold', 0.42)), 0.20, 0.80);
maxReductionDb = clamp(double(getParam(config, ...
    'deEsserMaxReductionDb', 4.0)), 0, 9);

if ratio <= threshold
    targetGain = 1;
else
    excess = min((ratio - threshold) / max(1 - threshold, eps), 1);
    reductionDb = maxReductionDb * excess;
    targetGain = 10 ^ (-reductionDb / 20);
end

frameSeconds = numel(x) / fs;
if targetGain < state.voice.deEsserGain
    alpha = exp(-frameSeconds / 0.025);
else
    alpha = exp(-frameSeconds / 0.12);
end
state.voice.deEsserGain = alpha * state.voice.deEsserGain + ...
    (1 - alpha) * targetGain;
y = lowPart + state.voice.deEsserGain * highPart;
end

function [y, state] = smoothedRmsMatch(y, reference, state, maxCorrectionDb)
y = cleanColumn(y);
reference = cleanColumn(reference);
rmsY = sqrt(mean(y .^ 2));
rmsRef = sqrt(mean(reference .^ 2));
if rmsY <= 1e-7 || rmsRef <= 1e-7
    return;
end

targetGain = rmsRef / rmsY;
maxGain = 10 ^ (abs(double(maxCorrectionDb)) / 20);
targetGain = clamp(targetGain, 1 / maxGain, maxGain);
if ~isfield(state.voice, 'rmsGain') || ~isfinite(state.voice.rmsGain)
    state.voice.rmsGain = 1;
end
state.voice.rmsGain = 0.92 * state.voice.rmsGain + 0.08 * targetGain;
y = y * state.voice.rmsGain;
end

function [y, state] = speechBandShape(x, fs, state, lowCutoff, highCutoff)
if ~isfield(state.voice, 'bandPrev') || numel(state.voice.bandPrev) ~= 2
    state.voice.bandPrev = zeros(2, 1);
end
[lowPassed, state.voice.bandPrev(2)] = onePoleLowpass( ...
    x, fs, highCutoff, state.voice.bandPrev(2));
[lowRumble, state.voice.bandPrev(1)] = onePoleLowpass( ...
    lowPassed, fs, lowCutoff, state.voice.bandPrev(1));
y = lowPassed - lowRumble;
end

function y = addGentleRoughness(x, fs, config, state, amount)
roughness = clamp01(getField(config, 'roughness', amount));
modFreq = abs(double(getField(config, 'modFreq', 5.5)));
if ~isfinite(modFreq) || modFreq <= 0, modFreq = 5.5; end
n = (0:numel(x)-1).' + state.voice.sampleIndex;
depth = min(0.055, 0.02 + 0.05 * roughness);
tremolo = 1 - depth + depth * sin(2 * pi * modFreq * n / fs);
y = x .* tremolo;
end

function y = robotVoice(x, fs, config, state)
intensity = clamp01(getField(config, 'intensity', 0.6));
modFreq = abs(double(getField(config, 'modFreq', 45)));
if ~isfinite(modFreq) || modFreq <= 0, modFreq = 45; end
modFreq = min(modFreq, fs * 0.25);
n = (0:numel(x)-1).' + state.voice.sampleIndex;
carrier = cos(2 * pi * modFreq * n / fs);
y = x .* ((1 - 0.30 * intensity) + 0.72 * intensity * carrier);
y = softLimitLocal(y, 1.06);
end

function [state, gate] = updateSpeechGate(state, x, fs, config)
rmsValue = sqrt(mean(x .^ 2));
frameDb = 20 * log10(rmsValue + eps);
thresholdDb = double(getParam(config, 'silenceBypassDb', -58));
if frameDb >= thresholdDb + 8
    target = 1;
elseif frameDb <= thresholdDb
    target = 0;
else
    target = (frameDb - thresholdDb) / 8;
end

if ~isfield(state.voice, 'speechGateValue') || ...
        ~isfinite(state.voice.speechGateValue)
    state.voice.speechGateValue = 0;
end
frameSeconds = numel(x) / fs;
if target > state.voice.speechGateValue
    alpha = exp(-frameSeconds / 0.035);
else
    alpha = exp(-frameSeconds / 0.18);
end
startValue = state.voice.speechGateValue;
endValue = alpha * startValue + (1 - alpha) * target;
state.voice.speechGateValue = clamp01(endValue);

if numel(x) <= 1
    gate = state.voice.speechGateValue;
else
    gate = linspace(startValue, state.voice.speechGateValue, numel(x)).';
end
end

function [state, ramp] = updateWetRamp(state, frameLength, fs, voiceType, config)
hasUsablePlan = isfield(state.voice, 'adaptiveConfig') && ...
    isstruct(state.voice.adaptiveConfig) && ...
    isfield(state.voice.adaptiveConfig, 'pitchShift') && ...
    isfinite(double(state.voice.adaptiveConfig.pitchShift));
ready = strcmpi(styleFamily(voiceType), 'robot_voice') || ...
    startsWith(char(state.voice.calibrationStatus), 'ready') || ...
    strcmp(state.voice.calibrationStatus, 'disabled') || hasUsablePlan;

target = double(ready);
startValue = state.voice.wetRampValue;
rampTime = clamp(double(getParam(config, 'wetRampTime', 0.06)), 0.015, 0.20);
step = frameLength / max(rampTime * fs, 1);
endValue = startValue + clamp(target - startValue, -step, step);
endValue = clamp01(endValue);
if frameLength <= 1
    ramp = endValue;
else
    ramp = linspace(startValue, endValue, frameLength).';
end
state.voice.wetRampValue = endValue;
end

function [y, prev] = onePoleLowpass(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff), 1), 0.45 * fs);
alpha = exp(-2 * pi * cutoff / fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1 - alpha) * x(n) + alpha * prev;
    y(n) = prev;
end
end

function y = softLimitLocal(x, drive)
drive = max(0.1, double(drive));
y = tanh(drive * x) / tanh(drive);
end

% =========================================================================
% Utility helpers
% =========================================================================
function config = fillVoiceDefaults(config)
defaults = makeDefaultConfig();
fields = fieldnames(defaults.voice);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name)
        config.(name) = defaults.voice.(name);
    end
end
if ~isfield(config, 'params') || isempty(config.params)
    config.params = defaults.voice.params;
else
    pFields = fieldnames(defaults.voice.params);
    for k = 1:numel(pFields)
        name = pFields{k};
        if ~isfield(config.params, name)
            config.params.(name) = defaults.voice.params.(name);
        end
    end
end
end

function voiceType = getVoiceType(config)
if isfield(config, 'type') && ~isempty(config.type)
    voiceType = char(config.type);
elseif isfield(config, 'mode') && ~isempty(config.mode)
    voiceType = char(config.mode);
else
    voiceType = 'none';
end
end

function family = styleFamily(mode)
mode = lower(strtrim(char(mode)));
switch mode
    case {'male', 'male_deep_gentle'}
        family = 'male';
    case {'female', 'female_gentle_sweet'}
        family = 'female';
    case {'child', 'child_bright_soft'}
        family = 'child';
    case {'elder', 'elder_warm_steady'}
        family = 'elder';
    case {'robot', 'robot_voice'}
        family = 'robot_voice';
    case 'anonymous'
        family = 'anonymous';
    otherwise
        family = 'none';
end
end

function value = getField(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function value = getParam(config, fieldName, defaultValue)
if isfield(config, 'params') && isstruct(config.params) && ...
        isfield(config.params, fieldName) && ~isempty(config.params.(fieldName))
    value = config.params.(fieldName);
else
    value = defaultValue;
end
end

function value = clamp(value, low, high)
value = min(max(double(value), low), high);
end

function value = clamp01(value)
value = clamp(value, 0, 1);
end

function x = cleanColumn(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end
