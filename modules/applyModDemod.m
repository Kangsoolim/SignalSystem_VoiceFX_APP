function [modSig, demodSig, state] = applyModDemod(x, fs, modDemodConfig, state)
%APPLYMODDEMOD Stateful AM modulation, coherent demodulation, or round trip.
%   [MODSIG, DEMODSIG, STATE] = APPLYMODDEMOD(X, FS, CONFIG, STATE)
%   supports:
%       none          - pass through
%       am_modulate   - conventional DSB-LC AM modulation
%       am_demodulate - coherent product detection + causal lowpass
%       am_roundtrip  - modulate and demodulate in one stateful call
%
%   The module is frame-safe: carrier phase and lowpass filter memory are
%   carried in STATE. receiverCarrierFreq and receiverPhase can be used to
%   study coherent receiver mismatch without changing the transmitter.

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

inputSignal = cleanColumn(x);
modSig = inputSignal;
demodSig = inputSignal;

if ~isfield(modDemodConfig, 'enabled') || ~modDemodConfig.enabled
    return;
end

mode = getModDemodMode(modDemodConfig);
if strcmpi(mode, 'none') || isempty(inputSignal)
    return;
end

if isempty(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('applyModDemod:InvalidSampleRate', ...
        'Sample rate must be a positive finite scalar.');
end

transmitCarrierFreq = sanitizeCarrier(getFieldOrDefault( ...
    modDemodConfig, 'carrierFreq', 4000), fs);
transmitPhase = finiteScalar(getFieldOrDefault( ...
    modDemodConfig, 'initialPhase', 0), 0);

receiverCarrierFreq = getFieldOrDefault(modDemodConfig, ...
    'receiverCarrierFreq', []);
if isempty(receiverCarrierFreq)
    receiverCarrierFreq = transmitCarrierFreq;
else
    receiverCarrierFreq = sanitizeCarrier(receiverCarrierFreq, fs);
end
receiverPhase = getFieldOrDefault(modDemodConfig, 'receiverPhase', []);
if isempty(receiverPhase)
    receiverPhase = transmitPhase;
else
    receiverPhase = finiteScalar(receiverPhase, transmitPhase);
end

signature = sprintf('%s_fs%.9g_tx%.9g_tp%.9g_rx%.9g_rp%.9g', ...
    lower(mode), fs, transmitCarrierFreq, transmitPhase, ...
    receiverCarrierFreq, receiverPhase);
if ~isfield(state.modDemod, 'signature') || ...
        ~strcmp(state.modDemod.signature, signature)
    state.modDemod.sampleIndex = 0;
    state.modDemod.lowpassZi = [];
    state.modDemod.signature = signature;
end
if ~isfield(state.modDemod, 'sampleIndex') || ...
        ~isscalar(state.modDemod.sampleIndex) || ...
        ~isfinite(state.modDemod.sampleIndex)
    state.modDemod.sampleIndex = 0;
end

sampleIndex = double(state.modDemod.sampleIndex);
transmitCarrier = makeCarrier(numel(inputSignal), fs, ...
    transmitCarrierFreq, transmitPhase, sampleIndex);
receiverCarrier = makeCarrier(numel(inputSignal), fs, ...
    receiverCarrierFreq, receiverPhase, sampleIndex);

switch lower(mode)
    case 'am_modulate'
        modSig = amModulate(inputSignal, transmitCarrier, modDemodConfig);
        demodSig = modSig;

    case 'am_demodulate'
        modSig = inputSignal;
        [demodSig, state] = amDemodulate(inputSignal, receiverCarrier, ...
            fs, modDemodConfig, state);

    case 'am_roundtrip'
        modSig = amModulate(inputSignal, transmitCarrier, modDemodConfig);
        [demodSig, state] = amDemodulate(modSig, receiverCarrier, ...
            fs, modDemodConfig, state);

    otherwise
        modSig = inputSignal;
        demodSig = inputSignal;
end

state.modDemod.sampleIndex = sampleIndex + numel(inputSignal);
state.modDemod.lastMode = mode;
state.modDemod.lastFs = fs;
state.modDemod.lastCarrierFreq = transmitCarrierFreq;
state.modDemod.lastReceiverCarrierFreq = receiverCarrierFreq;
state.modDemod.lastReceiverPhase = receiverPhase;

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
mode = lower(strtrim(mode));
end

function carrierFreq = sanitizeCarrier(carrierFreq, fs)
carrierFreq = abs(finiteScalar(carrierFreq, min(4000, 0.35 * fs)));
nyquist = fs / 2;
if carrierFreq <= 0 || carrierFreq >= nyquist
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
mu = min(max(abs(finiteScalar(mu, 0.7)), 0), 1.5);

messageScale = getFieldOrDefault(config, 'messageScale', 0.8);
messageScale = min(max(abs(finiteScalar(messageScale, 0.8)), 0), 1);

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
[b, a, filterSignature] = designLowpass(fs, config);
useZeroPhase = isTruthy(getFieldOrDefault(config, 'useZeroPhase', false));
minFiltFiltLength = 3 * max(numel(a), numel(b));

if useZeroPhase && exist('filtfilt', 'file') == 2 && ...
        numel(raw) > minFiltFiltLength
    y = filtfilt(b, a, raw);
else
    ziLength = max(numel(a), numel(b)) - 1;
    if ziLength > 0
        if ~isfield(state.modDemod, 'lowpassSignature') || ...
                ~strcmp(state.modDemod.lowpassSignature, filterSignature) || ...
                ~isfield(state.modDemod, 'lowpassZi') || ...
                numel(state.modDemod.lowpassZi) ~= ziLength
            zi = zeros(ziLength, 1);
        else
            zi = state.modDemod.lowpassZi(:);
        end
        [y, zi] = filter(b, a, raw, zi);
        state.modDemod.lowpassZi = zi;
    else
        y = filter(b, a, raw);
    end
end

% Conventional AM contains a DC term after coherent product detection.
% Full-file/report mode removes the block mean. In frame mode the AM branch
% remains opt-in and disabled by default, so this behavior does not affect
% the normal realtime voice chain.
y = y - mean(y);

% Full-file report exports can normalize recovered AM audio for convenient
% listening. Avoid this option in per-frame realtime paths.
if isTruthy(getFieldOrDefault(config, 'normalizeOutput', true))
    peak = max(abs(y));
    if peak > eps
        y = 0.95 * y / peak;
    end
end
state.modDemod.lowpassSignature = filterSignature;
end

function [b, a, signature] = designLowpass(fs, config)
nyquist = fs / 2;
cutoff = getFieldOrDefault(config, 'lowpassCutoff', 3400);
cutoff = abs(finiteScalar(cutoff, min(3400, 0.35 * fs)));
if cutoff <= 0 || cutoff >= nyquist
    cutoff = min(3400, 0.35 * fs);
end
cutoff = min(max(cutoff, 1), nyquist * 0.95);

order = getFieldOrDefault(config, 'filterOrder', 4);
order = round(abs(finiteScalar(order, 4)));
order = max(1, min(order, 8));

if exist('butter', 'file') == 2
    [b, a] = butter(order, cutoff / nyquist, 'low');
else
    % First-order fallback keeps the module runnable without Signal
    % Processing Toolbox while preserving causal state behavior.
    alpha = exp(-2 * pi * cutoff / fs);
    b = 1 - alpha;
    a = [1, -alpha];
end
signature = sprintf('lp_fs%.9g_fc%.9g_order%d', fs, cutoff, order);
end

function value = getFieldOrDefault(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
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

function value = finiteScalar(value, fallback)
value = double(value);
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = fallback;
end
end

function tf = isTruthy(value)
if islogical(value) || isnumeric(value)
    tf = ~isempty(value) && any(value(:) ~= 0);
else
    text = lower(strtrim(char(value)));
    tf = any(strcmp(text, {'true','on','yes','1'}));
end
end
