function [modSig, demodSig, state] = applyModDemod(x, fs, modDemodConfig, state)
%APPLYMODDEMOD Apply basic AM modulation or coherent demodulation.
%   The three-output interface is kept for report workflows:
%       [modSig, demodSig, state] = applyModDemod(...)
%   For am_modulate, both modSig and demodSig carry the modulated signal so
%   processAudioFrame can keep using the second output as the primary signal.
%   M08 is intended for file-mode/report figures that show carrier-sideband
%   spectrum shifting and lowpass recovery. Keep modDemod.enabled false for
%   ordinary realtime voice/effect processing unless a dedicated App panel
%   explicitly opts into this demonstration.

if nargin < 3 || isempty(modDemodConfig)
    modDemodConfig = struct('enabled', false, 'mode', 'none', 'params', struct());
end
modDemodConfig = fillModDemodDefaults(modDemodConfig);

if nargin < 4 || isempty(state)
    state = initProcessState();
end
if ~isfield(state, 'modDemod') || isempty(state.modDemod)
    state.modDemod = struct();
end

modSig = double(x);
modSig = modSig(:);
modSig(~isfinite(modSig)) = 0;
demodSig = modSig;

if ~isfield(modDemodConfig, 'enabled') || ~modDemodConfig.enabled
    return;
end

mode = getModDemodMode(modDemodConfig);
if strcmpi(mode, 'none') || isempty(modSig)
    return;
end

if isempty(fs) || ~isfinite(fs) || fs <= 0
    modSig(~isfinite(modSig)) = 0;
    demodSig = modSig;
    return;
end

carrierFreq = sanitizeCarrier(getFieldOrDefault(modDemodConfig, 'carrierFreq', 4000), fs);
initialPhase = getFieldOrDefault(modDemodConfig, 'initialPhase', 0);
signature = sprintf('%s_fs%.9g_fc%.9g_phase%.9g', lower(mode), fs, carrierFreq, double(initialPhase));
if ~isfield(state.modDemod, 'signature') || ~strcmp(state.modDemod.signature, signature)
    state.modDemod.sampleIndex = 0;
    state.modDemod.lowpassZi = [];
    state.modDemod.signature = signature;
end

carrier = makeCarrier(numel(modSig), fs, carrierFreq, double(initialPhase), state.modDemod.sampleIndex);

switch lower(mode)
    case 'am_modulate'
        modSig = amModulate(modSig, carrier, modDemodConfig);
        demodSig = modSig;

    case 'am_demodulate'
        [demodSig, state] = amDemodulate(modSig, carrier, fs, modDemodConfig, state);

    otherwise
        demodSig = modSig;
end

state.modDemod.sampleIndex = state.modDemod.sampleIndex + numel(modSig);
state.modDemod.lastMode = mode;
state.modDemod.lastFs = fs;
state.modDemod.lastCarrierFreq = carrierFreq;

modSig = cleanColumn(modSig);
demodSig = cleanColumn(demodSig);
end

function config = fillModDemodDefaults(config)
defaults = makeDefaultConfig();
defaultConfig = defaults.modDemod;
fields = fieldnames(defaultConfig);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name)
        config.(name) = defaultConfig.(name);
    end
end
end

function mode = getModDemodMode(config)
if isfield(config, 'type') && ~isempty(config.type)
    mode = char(config.type);
elseif isfield(config, 'mode') && ~isempty(config.mode)
    mode = char(config.mode);
else
    mode = 'none';
end
end

function carrierFreq = sanitizeCarrier(carrierFreq, fs)
carrierFreq = abs(double(carrierFreq));
nyquist = fs / 2;
if isempty(carrierFreq) || ~isfinite(carrierFreq) || carrierFreq <= 0 || carrierFreq >= nyquist
    carrierFreq = min(4000, 0.35 * fs);
end
carrierFreq = min(max(carrierFreq, 1), nyquist * 0.95);
end

function carrier = makeCarrier(numSamples, fs, carrierFreq, initialPhase, sampleIndex)
n = (0:numSamples-1).' + double(sampleIndex);
carrier = cos(2 * pi * carrierFreq * n / fs + initialPhase);
end

function y = amModulate(x, carrier, config)
mu = getFieldOrDefault(config, 'modulationIndex', 0.7);
mu = min(max(abs(double(mu)), 0), 1.5);

messageScale = getFieldOrDefault(config, 'messageScale', 0.8);
messageScale = min(max(abs(double(messageScale)), 0), 1);

m = cleanColumn(x);
peak = max(abs(m));
if peak > eps
    m = m / peak * messageScale;
end

envelope = 1 + mu * m;
y = envelope .* carrier;
safePeak = max(abs(y));
if safePeak > 1
    y = y / safePeak;
end
end

function [y, state] = amDemodulate(x, carrier, fs, config, state)
raw = 2 * cleanColumn(x) .* carrier;
[b, a, signature] = designLowpass(fs, config);
useZeroPhase = isTruthy(getFieldOrDefault(config, 'useZeroPhase', false));
minFiltFiltLength = 3 * max(numel(a), numel(b));

if useZeroPhase && exist('filtfilt', 'file') == 2 && numel(raw) > minFiltFiltLength
    y = filtfilt(b, a, raw);
else
    ziLength = max(numel(a), numel(b)) - 1;
    if ziLength > 0
        if ~isfield(state.modDemod, 'lowpassSignature') || ~strcmp(state.modDemod.lowpassSignature, signature) || ...
                ~isfield(state.modDemod, 'lowpassZi') || numel(state.modDemod.lowpassZi) ~= ziLength
            zi = zeros(ziLength, 1);
        else
            zi = state.modDemod.lowpassZi;
        end
        [y, zi] = filter(b, a, raw, zi);
        state.modDemod.lowpassZi = zi;
    else
        y = filter(b, a, raw);
    end
end

y = y - mean(y);
% Full-file report exports can normalize recovered AM audio for convenient
% listening. Avoid this in per-frame realtime paths because each frame would
% be scaled independently.
if isTruthy(getFieldOrDefault(config, 'normalizeOutput', true))
    peak = max(abs(y));
    if peak > eps
        y = 0.95 * y / peak;
    end
end
state.modDemod.lowpassSignature = signature;
end

function [b, a, signature] = designLowpass(fs, config)
nyquist = fs / 2;
cutoff = getFieldOrDefault(config, 'lowpassCutoff', 3400);
cutoff = abs(double(cutoff));
if isempty(cutoff) || ~isfinite(cutoff) || cutoff <= 0 || cutoff >= nyquist
    cutoff = min(3400, 0.35 * fs);
end
cutoff = min(max(cutoff, 1), nyquist * 0.95);

order = getFieldOrDefault(config, 'filterOrder', 4);
order = round(abs(double(order)));
if isempty(order) || ~isfinite(order)
    order = 4;
end
order = max(1, min(order, 8));

if exist('butter', 'file') == 2
    [b, a] = butter(order, cutoff / nyquist, 'low');
else
    alpha = exp(-2 * pi * cutoff / fs);
    b = 1 - alpha;
    a = [1, -alpha];
end
signature = sprintf('lp_fs%.9g_fc%.9g_order%d', fs, cutoff, order);
end

function value = getFieldOrDefault(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function x = cleanColumn(x)
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
end

function tf = isTruthy(value)
if islogical(value) || isnumeric(value)
    tf = any(value(:) ~= 0);
else
    tf = strcmpi(char(value), 'true') || strcmpi(char(value), 'on') || strcmpi(char(value), 'yes');
end
end
