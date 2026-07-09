function [y, diagnostics] = processVoiceFileHQ(x, fs, voiceConfig)
%PROCESSVOICEFILEHQ Naturalness-priority full-file voice transformation.
%   This offline file engine analyzes the complete utterance, plans a mild
%   source-adaptive transformation, and preserves timing/prosody.
%
%   Processing:
%       source profile
%       -> naturalness-priority adaptive planner
%       -> full-file phase-locked pitch shift
%       -> light spectral-envelope warp
%       -> very mild timbre/excitation shaping
%       -> gentle style dynamics
%       -> optional de-essing
%       -> limited loudness matching
%
%   No hard fixed target F0 is imposed. Broad class regions guide the
%   direction only, while the source profile decides how much processing is
%   safe and useful.

if nargin < 3 || isempty(voiceConfig)
    defaults = makeDefaultConfig();
    voiceConfig = defaults.voice;
end
voiceConfig = fillDefaults(voiceConfig);

validateattributes(fs, {'numeric'}, ...
    {'scalar','real','finite','positive'}, mfilename, 'fs');

x = double(x);
if isempty(x)
    y = zeros(0,1);
    diagnostics = struct('status','empty','engine','none');
    return;
end
if ~isvector(x)
    x = robustVoiceDownmix(x);
end
x = x(:);
x(~isfinite(x)) = 0;

mode = getVoiceType(voiceConfig);
diagnostics = struct();
diagnostics.status = 'ok';
diagnostics.mode = mode;
diagnostics.engine = 'offline_natural_adaptive';
diagnostics.usedShiftPitch = false;
diagnostics.usedFormantPreservation = false;
diagnostics.usedFallback = false;

if ~voiceConfig.enabled || strcmpi(mode,'none')
    y = x;
    diagnostics.status = 'bypass';
    return;
end

profile = analyzeVoiceProfile(x, fs);
[adaptiveConfig, adaptiveDiagnostics] = ...
    adaptVoiceStyleConfig(profile, voiceConfig);

diagnostics.sourceProfile = profile;
diagnostics.adaptive = adaptiveDiagnostics;

if strcmpi(styleFamily(mode),'robot_voice')
    y = offlineRobot(x, fs, adaptiveConfig);
    diagnostics.engine = 'offline_robot';
    y = transparentSoftLimit(y, 0.98, 0.82);
    return;
end

semitones = getField(adaptiveConfig, 'pitchShift', 0);
diagnostics.pitchShiftSemitones = semitones;

[shifted, shiftInfo] = highQualityShift(x, semitones, adaptiveConfig);
diagnostics.usedShiftPitch = shiftInfo.usedShiftPitch;
diagnostics.usedFormantPreservation = shiftInfo.usedFormantPreservation;
diagnostics.usedFallback = shiftInfo.usedFallback;
diagnostics.shiftMessage = shiftInfo.message;

shifted = matchLength(shifted, numel(x));
family = styleFamily(mode);

% Light envelope transformation. The aggressive HQ cepstral warp and the
% separate elder micro-delay stage are intentionally not used because they
% reduced naturalness in listening tests.
hqState = initProcessState();
hqState.voice.sampleIndex = 0;
[shaped, hqState] = warpSpectralEnvelope( ...
    shifted, fs, adaptiveConfig, hqState);

shaped = offlineTimbreShape(shaped, fs, adaptiveConfig, family);
[shaped, hqState] = shapeVoiceExcitation( ...
    shaped, fs, adaptiveConfig, hqState);
[shaped, hqState] = applyStyleDynamics( ...
    shaped, fs, adaptiveConfig, hqState);

shaped = offlineDeEss(shaped, fs, adaptiveConfig, family);
shaped = limitedRmsMatch(shaped, x, 1.0);

% Full transformed signal is used by default. Mixing dry and pitch-shifted
% speech can create combing/chorus artifacts. The mix control remains
% available for manual preview but defaults to 1.
mixAmount = clamp01(getField(adaptiveConfig, 'mix', 1.0));
if mixAmount >= 0.999
    y = shaped;
else
    y = (1-mixAmount)*x + mixAmount*shaped;
end

y = finiteColumn(y);
y = transparentSoftLimit(y, 0.98, 0.84);
end

% -------------------------------------------------------------------------
function mono = robustVoiceDownmix(x)
channelRms = sqrt(mean(double(x).^2,1));
[dominantRms, dominantIndex] = max(channelRms);
weightSum = sum(channelRms);
if weightSum <= eps
    mono = mean(x,2);
else
    weights = channelRms/weightSum;
    mono = double(x)*weights(:);
    monoRms = sqrt(mean(mono.^2));
    if dominantRms > eps && monoRms < 0.30*dominantRms
        mono = double(x(:,dominantIndex));
    end
end
mono = mono(:);
mono(~isfinite(mono)) = 0;
end

function [y, info] = highQualityShift(x, semitones, config)
info = struct('usedShiftPitch',false, ...
    'usedFormantPreservation',false, ...
    'usedFallback',false, ...
    'message','');

if abs(semitones) < 0.02
    y = x;
    info.message = 'no_shift_needed';
    return;
end

lockPhase = logical(getParam(config,'offlineLockPhase',true));
preserveFormants = logical(getParam(config, ...
    'offlinePreserveFormants',true));
cepstralOrder = round(clamp(double(getParam(config, ...
    'offlineCepstralOrder',30)),0,100));

if exist('shiftPitch','file') == 2
    try
        [analysisWindow, overlapLength] = makePitchWindow(numel(x));
        if isempty(analysisWindow)
            y = shiftPitch(x,semitones, ...
                'LockPhase',lockPhase, ...
                'PreserveFormants',preserveFormants, ...
                'CepstralOrder',cepstralOrder);
        else
            y = shiftPitch(x,semitones, ...
                'Window',analysisWindow, ...
                'OverlapLength',overlapLength, ...
                'LockPhase',lockPhase, ...
                'PreserveFormants',preserveFormants, ...
                'CepstralOrder',cepstralOrder);
        end
        info.usedShiftPitch = true;
        info.usedFormantPreservation = preserveFormants;
        info.message = 'phase_locked_formant_preserved';
        return;
    catch firstError
        try
            y = shiftPitch(x,semitones, ...
                'LockPhase',lockPhase, ...
                'PreserveFormants',preserveFormants, ...
                'CepstralOrder',cepstralOrder);
            info.usedShiftPitch = true;
            info.usedFormantPreservation = preserveFormants;
            info.message = ['default_window_retry: ', firstError.message];
            return;
        catch secondError
            try
                y = shiftPitch(x,semitones,'LockPhase',lockPhase);
                info.usedShiftPitch = true;
                info.message = ['phase_locked_without_formants: ', ...
                    secondError.message];
                return;
            catch thirdError
                info.message = ['shiftPitch_failed: ', thirdError.message];
            end
        end
    end
end

% Safe bypass fallback. Do not fabricate a low-quality resampling-based
% pitch shift because that would also alter speech duration.
y = x;
info.usedFallback = true;
if isempty(info.message)
    info.message = 'shiftPitch_unavailable_bypass_pitch';
end
end

function [window, overlapLength] = makePitchWindow(signalLength)
if signalLength < 512
    window = [];
    overlapLength = [];
    return;
end

windowLength = min(2048, 2^floor(log2(double(signalLength))));
windowLength = max(windowLength,512);
index = (0:windowLength-1).';
periodicHann = 0.5 - 0.5*cos(2*pi*index/windowLength);
window = sqrt(max(periodicHann,0));
overlapLength = round(0.75*windowLength);
end

function y = offlineTimbreShape(x, fs, config, mode)
[low, ~] = onePoleLowpass(x, fs, 240, 0);
[belowBody, ~] = onePoleLowpass(x, fs, 1000, 0);
[belowPresence, ~] = onePoleLowpass(x, fs, min(3200,0.38*fs), 0);

body = belowBody-low;
presence = belowPresence-belowBody;
air = x-belowPresence;

lowGain = clamp(double(getField(config,'lowGain',0)),-0.08,0.08);
highGain = clamp(double(getField(config,'highGain',0)),-0.08,0.08);
intensity = clamp01(getField(config,'intensity',0.72));

switch lower(mode)
    case 'male'
        bodyGain = 0.026*intensity;
        presenceGain = 0.014*intensity;
    case 'female'
        bodyGain = -0.008*intensity;
        presenceGain = 0.018*intensity;
    case 'child'
        bodyGain = -0.014*intensity;
        presenceGain = 0.014*intensity;
    case 'elder'
        bodyGain = 0.008*intensity;
        presenceGain = -0.018*intensity;
    otherwise
        bodyGain = 0;
        presenceGain = 0;
end

y = x + lowGain*low + bodyGain*body + ...
    presenceGain*presence + highGain*air;
end

function y = offlineDeEss(x, fs, config, mode)
if ~any(strcmpi(mode,{'female','child'})) || ...
        ~logical(getParam(config,'deEsserEnabled',true))
    y = x;
    return;
end

if strcmpi(mode,'child')
    cutoff = min(4300,0.36*fs);
    defaultThreshold = 0.34;
    defaultReductionDb = 5.0;
else
    cutoff = min(5200,0.40*fs);
    defaultThreshold = 0.42;
    defaultReductionDb = 3.0;
end
if cutoff <= 1000
    y = x;
    return;
end

[low, ~] = onePoleLowpass(x, fs, cutoff, 0);
high = x-low;
ratio = sqrt(mean(high.^2))/(sqrt(mean(x.^2))+eps);
threshold = clamp(double(getParam(config, ...
    'deEsserThreshold',defaultThreshold)),0.2,0.8);
maxReductionDb = clamp(double(getParam(config, ...
    'deEsserMaxReductionDb',defaultReductionDb)),0,6);

if ratio <= threshold
    gain = 1;
else
    excess = min((ratio-threshold)/max(1-threshold,eps),1);
    gain = 10^(-(maxReductionDb*excess)/20);
end
y = low + gain*high;
end

function y = offlineRobot(x, fs, config)
intensity = clamp01(getField(config,'intensity',0.6));
modFreq = abs(double(getField(config,'modFreq',45)));
if ~isfinite(modFreq) || modFreq <= 0
    modFreq = 45;
end
modFreq = min(modFreq,0.25*fs);
t = (0:numel(x)-1).'/fs;
carrier = cos(2*pi*modFreq*t);
y = x.*((1-0.30*intensity)+0.72*intensity*carrier);
end

function y = limitedRmsMatch(y, reference, maxCorrectionDb)
rmsY = sqrt(mean(y.^2));
rmsRef = sqrt(mean(reference.^2));
if rmsY <= 1e-8 || rmsRef <= 1e-8
    return;
end
maxGain = 10^(abs(maxCorrectionDb)/20);
gain = clamp(rmsRef/rmsY,1/maxGain,maxGain);
y = y*gain;
end

function y = transparentSoftLimit(x, peakLimit, kneeRatio)
x = finiteColumn(x);
peakLimit = clamp(abs(double(peakLimit)),0.1,1.0);
kneeRatio = clamp(double(kneeRatio),0.5,0.95);
knee = kneeRatio*peakLimit;
a = abs(x);
s = sign(x);
y = x;
mask = a > knee;
if any(mask)
    z = (a(mask)-knee)/max(peakLimit-knee,eps);
    compressed = knee + (peakLimit-knee)*tanh(z)/tanh(1);
    y(mask) = s(mask).*compressed;
end
y = min(max(y,-peakLimit),peakLimit);
end

function y = matchLength(y, targetLength)
y = finiteColumn(y);
if numel(y) < targetLength
    y(end+1:targetLength,1) = 0;
elseif numel(y) > targetLength
    y = y(1:targetLength);
end
end

function [y, prev] = onePoleLowpass(x, fs, cutoff, prev)
cutoff = min(max(double(cutoff),1),0.45*fs);
alpha = exp(-2*pi*cutoff/fs);
y = zeros(size(x));
for n = 1:numel(x)
    prev = (1-alpha)*x(n)+alpha*prev;
    y(n) = prev;
end
end

function config = fillDefaults(config)
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

function family = styleFamily(mode)
mode = lower(strtrim(char(mode)));
switch mode
    case {'male','male_deep_gentle'}
        family = 'male';
    case {'female','female_gentle_sweet'}
        family = 'female';
    case {'child','child_bright_soft'}
        family = 'child';
    case {'elder','elder_warm_steady'}
        family = 'elder';
    case {'robot','robot_voice'}
        family = 'robot_voice';
    case 'anonymous'
        family = 'anonymous';
    otherwise
        family = 'none';
end
end

function value = getField(s,name,defaultValue)
if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function value = getParam(config,name,defaultValue)
if isfield(config,'params') && isstruct(config.params) && ...
        isfield(config.params,name) && ~isempty(config.params.(name))
    value = config.params.(name);
else
    value = defaultValue;
end
end

function value = clamp(value,low,high)
value = min(max(double(value),low),high);
end

function value = clamp01(value)
value = clamp(value,0,1);
end

function x = finiteColumn(x)
x = double(x(:));
x(~isfinite(x)) = 0;
end
