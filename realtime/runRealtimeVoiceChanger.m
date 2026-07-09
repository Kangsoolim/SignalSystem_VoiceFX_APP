function stats = runRealtimeVoiceChanger(durationSeconds, voiceMode, options)
%RUNREALTIMEVOICECHANGER Interactive low-latency microphone VoiceFX runner.
%   STATS = RUNREALTIMEVOICECHANGER(DURATIONSECONDS, VOICEMODE, OPTIONS)
%   keeps processAudioFrame as the single DSP core while adding optional
%   Dashboard callbacks, rolling telemetry, live parameter updates, and two
%   audio I/O strategies.
%
%   Basic examples:
%       runRealtimeVoiceChanger(20, 'female')
%       runRealtimeVoiceChanger(Inf, 'anonymous', options)
%
%   OPTIONS fields (all optional):
%       sampleRate          default 48000
%       frameLength         default 512
%       ioMode              'split' (reader+writer) or 'duplex'
%       inputDevice         split-mode input device name
%       outputDevice        split-mode output device name
%       duplexDevice        audioPlayerRecorder device name
%       intensity           voice intensity [0,1]
%       enableSpeechClean   default true
%       fxMode/fxMix/fxIntensity
%       spaceMode/spaceMix
%       monitorInterval     telemetry callback period, default 0.10 s
%       controlInterval     live config callback period, default 0.08 s
%       rollingWindowSeconds telemetry window, default 3 s
%       monitorFcn          @(snapshot) callback
%       controlFcn          @() full config or option-update struct
%       stopFcn             @() logical stop request
%       processUIEvents     call drawnow limitrate at monitor cadence
%
%   'duplex' uses audioPlayerRecorder where available. 'split' preserves the
%   original reader/writer path and supports separate input/output devices.
%   The reported nominalBufferBudgetMs is an internal scheduling indicator,
%   not a measured acoustic round-trip latency.

if nargin < 1 || isempty(durationSeconds)
    durationSeconds = 20;
end
if nargin < 2 || isempty(voiceMode)
    voiceMode = 'female';
end
if nargin < 3 || isempty(options)
    options = struct();
end

validateDuration(durationSeconds);
fs = positiveScalar(getOpt(options, 'sampleRate', 48000), 48000);
frameLength = round(positiveScalar(getOpt(options, 'frameLength', 512), 512));
if frameLength < 32
    error('runRealtimeVoiceChanger:InvalidFrameLength', ...
        'frameLength must be at least 32 samples.');
end
ioMode = lower(canonicalText(getOpt(options, 'ioMode', 'split'), 'split'));
if ~any(strcmp(ioMode, {'split', 'duplex'}))
    error('runRealtimeVoiceChanger:InvalidIOMode', ...
        'ioMode must be ''split'' or ''duplex''.');
end

monitorInterval = clampFinite(getOpt(options, 'monitorInterval', 0.10), ...
    0.05, 5.0, 0.10);
controlInterval = clampFinite(getOpt(options, 'controlInterval', 0.08), ...
    0.05, 5.0, 0.08);
rollingWindowSeconds = clampFinite(getOpt(options, ...
    'rollingWindowSeconds', 3.0), 0.5, 60, 3.0);
monitorFcn = getOpt(options, 'monitorFcn', []);
controlFcn = getOpt(options, 'controlFcn', []);
stopFcn = getOpt(options, 'stopFcn', []);
processUIEvents = logicalScalar(getOpt(options, 'processUIEvents', false), false);
validateCallback(monitorFcn, 'monitorFcn');
validateCallback(controlFcn, 'controlFcn');
validateCallback(stopFcn, 'stopFcn');

config = buildRealtimeConfig(voiceMode, options);
config.audio.frameLength = frameLength;
state = initProcessState(config);

[io, ioCleanup] = openAudioIO(ioMode, fs, frameLength, options); %#ok<ASGLU>
cleanupObj = onCleanup(@()closeAudioIO(io)); %#ok<NASGU>

frameDuration = frameLength / fs;
rollingCapacity = max(8, ceil(rollingWindowSeconds / frameDuration));
rollingProcessTimes = zeros(rollingCapacity, 1);
rollingCount = 0;
rollingIndex = 0;

storeAllTimes = isfinite(durationSeconds);
if storeAllTimes
    expectedFrames = max(1, ceil(durationSeconds / frameDuration) + 32);
    processTimes = zeros(expectedFrames, 1);
else
    processTimes = zeros(0, 1);
end

frameCount = 0;
totalProcessTime = 0;
totalOverrun = 0;
totalUnderrun = 0;
lastMonitorTime = -Inf;
lastControlTime = -Inf;
monitorWarningIssued = false;
controlWarningIssued = false;
stopWarningIssued = false;
lastInputFrame = zeros(frameLength, 1);
lastOutputFrame = zeros(frameLength, 1);

fprintf('Realtime VoiceFX started: mode=%s, io=%s, fs=%g, frame=%d (%.2f ms)\n', ...
    char(voiceMode), ioMode, fs, frameLength, 1000 * frameDuration);
fprintf('Calibration %.2f s; press Ctrl+C or use stopFcn to stop.\n', ...
    config.voice.params.calibrationSeconds);

sessionTic = tic;
while toc(sessionTic) < durationSeconds
    elapsedBeforeFrame = toc(sessionTic);

    if ~isempty(stopFcn)
        try
            if logicalScalar(stopFcn(), false)
                break;
            end
        catch ME
            if ~stopWarningIssued
                warning('runRealtimeVoiceChanger:StopCallbackFailed', ...
                    'stopFcn failed and will be ignored: %s', ME.message);
                stopWarningIssued = true;
            end
        end
    end

    if ~isempty(controlFcn) && elapsedBeforeFrame - lastControlTime >= controlInterval
        try
            updateValue = controlFcn();
            config = applyControlUpdate(config, updateValue, frameLength);
            lastControlTime = elapsedBeforeFrame;
        catch ME
            if ~controlWarningIssued
                warning('runRealtimeVoiceChanger:ControlCallbackFailed', ...
                    'controlFcn failed; previous config retained: %s', ME.message);
                controlWarningIssued = true;
            end
            lastControlTime = elapsedBeforeFrame;
        end
    end

    if strcmp(ioMode, 'duplex')
        [xFrame, underrun, overrun] = io.duplex(lastOutputFrame);
    else
        [xFrame, overrun] = io.reader();
        underrun = 0;
    end
    xFrame = forceFrameLength(xFrame, frameLength);

    frameTic = tic;
    [yFrame, state] = processAudioFrame(xFrame, fs, config, state);
    processElapsed = toc(frameTic);
    yFrame = forceFrameLength(yFrame, frameLength);

    if strcmp(ioMode, 'duplex')
        % Full-duplex objects output the previous processed frame while the
        % current frame is captured; this is a deliberate one-frame queue.
        lastOutputFrame = yFrame;
    else
        underrun = io.writer(yFrame);
    end

    frameCount = frameCount + 1;
    totalProcessTime = totalProcessTime + processElapsed;
    totalOverrun = totalOverrun + double(overrun);
    totalUnderrun = totalUnderrun + double(underrun);
    lastInputFrame = xFrame;
    if strcmp(ioMode, 'split')
        lastOutputFrame = yFrame;
    end

    rollingIndex = mod(rollingIndex, rollingCapacity) + 1;
    rollingProcessTimes(rollingIndex) = processElapsed;
    rollingCount = min(rollingCount + 1, rollingCapacity);

    if storeAllTimes
        if frameCount > numel(processTimes)
            processTimes = [processTimes; zeros(max(1000, expectedFrames), 1)]; %#ok<AGROW>
        end
        processTimes(frameCount) = processElapsed;
    end

    elapsedNow = toc(sessionTic);
    shouldMonitor = elapsedNow - lastMonitorTime >= monitorInterval;
    if shouldMonitor
        snapshot = makeSnapshot(frameCount, elapsedNow, fs, frameLength, ...
            totalProcessTime, rollingProcessTimes, rollingCount, ...
            rollingIndex, totalOverrun, totalUnderrun, lastInputFrame, ...
            lastOutputFrame, config, ioMode);
        if ~isempty(monitorFcn)
            try
                monitorFcn(snapshot);
            catch ME
                if ~monitorWarningIssued
                    warning('runRealtimeVoiceChanger:MonitorCallbackFailed', ...
                        'monitorFcn failed; audio continues: %s', ME.message);
                    monitorWarningIssued = true;
                end
            end
        end
        if processUIEvents
            drawnow limitrate;
        end
        lastMonitorTime = elapsedNow;
    end
end

elapsedSeconds = toc(sessionTic);
if storeAllTimes
    processTimes = processTimes(1:frameCount);
else
    processTimes = orderedRollingValues(rollingProcessTimes, rollingCount, rollingIndex);
end

stats = struct();
stats.voiceMode = char(getConfigText(config.voice, {'type','mode'}, voiceMode));
stats.ioMode = ioMode;
stats.sampleRate = fs;
stats.frameLength = frameLength;
stats.frameDurationMs = 1000 * frameDuration;
stats.elapsedSeconds = elapsedSeconds;
stats.framesProcessed = frameCount;
stats.totalOverrunSamples = totalOverrun;
stats.totalUnderrunSamples = totalUnderrun;
if frameCount > 0
    stats.meanProcessMs = 1000 * totalProcessTime / frameCount;
    stats.p95ProcessMs = 1000 * percentileSimple(processTimes, 95);
    stats.maxProcessMs = 1000 * max(processTimes);
    stats.meanRealtimeFactor = (totalProcessTime / frameCount) / frameDuration;
else
    stats.meanProcessMs = NaN;
    stats.p95ProcessMs = NaN;
    stats.maxProcessMs = NaN;
    stats.meanRealtimeFactor = NaN;
end
stats.finalState = state;
stats.finalConfig = config;

fprintf('\nRealtime session finished.\n');
fprintf('  Frames          : %d\n', stats.framesProcessed);
fprintf('  Mean processing : %.2f ms/frame\n', stats.meanProcessMs);
fprintf('  P95 processing  : %.2f ms/frame\n', stats.p95ProcessMs);
fprintf('  Mean RTF        : %.3f\n', stats.meanRealtimeFactor);
fprintf('  Overrun samples : %d\n', totalOverrun);
fprintf('  Underrun samples: %d\n', totalUnderrun);
end

function [io, cleanupToken] = openAudioIO(ioMode, fs, frameLength, options)
io = struct('reader', [], 'writer', [], 'duplex', []);
cleanupToken = [];
if strcmp(ioMode, 'duplex')
    if isempty(which('audioPlayerRecorder'))
        error('runRealtimeVoiceChanger:AudioPlayerRecorderRequired', ...
            ['ioMode=''duplex'' requires Audio Toolbox audioPlayerRecorder. ', ...
             'Use ioMode=''split'' when it is unavailable.']);
    end
    args = {'SampleRate', fs, 'SupportVariableSize', false};
    device = getOpt(options, 'duplexDevice', '');
    if ~isempty(device)
        args = [args, {'Device', char(device)}]; %#ok<AGROW>
    end
    io.duplex = audioPlayerRecorder(args{:});
    setup(io.duplex, zeros(frameLength, 1));
else
    if isempty(which('audioDeviceReader')) || ...
            isempty(which('audioDeviceWriter'))
        error('runRealtimeVoiceChanger:AudioToolboxRequired', ...
            'audioDeviceReader/audioDeviceWriter are required for split mode.');
    end
    readerArgs = {'SampleRate', fs, 'SamplesPerFrame', frameLength, ...
        'NumChannels', 1};
    inputDevice = getOpt(options, 'inputDevice', '');
    if ~isempty(inputDevice)
        readerArgs = [readerArgs, {'Device', char(inputDevice)}]; %#ok<AGROW>
    end
    io.reader = audioDeviceReader(readerArgs{:});

    writerArgs = {'SampleRate', fs};
    outputDevice = getOpt(options, 'outputDevice', '');
    if ~isempty(outputDevice)
        writerArgs = [writerArgs, {'Device', char(outputDevice)}]; %#ok<AGROW>
    end
    io.writer = audioDeviceWriter(writerArgs{:});
    setup(io.reader);
    setup(io.writer, zeros(frameLength, 1));
end
end

function closeAudioIO(io)
fields = {'reader', 'writer', 'duplex'};
for k = 1:numel(fields)
    name = fields{k};
    if isfield(io, name) && ~isempty(io.(name))
        try
            release(io.(name));
        catch
        end
    end
end
end

function config = applyControlUpdate(config, updateValue, frameLength)
if isempty(updateValue)
    return;
end
if ~isstruct(updateValue)
    error('controlFcn must return a config struct, option-update struct, or empty.');
end
% A complete VoiceFX config contains the main processing-chain sections.
if all(isfield(updateValue, {'audio','voice','filter','fx','space','modDemod','output'}))
    candidate = updateValue;
else
    currentMode = getConfigText(config.voice, {'type','mode'}, 'female');
    candidate = buildRealtimeConfig(currentMode, updateValue, config);
end
candidate.audio.frameLength = frameLength;
config = candidate;
end

function snapshot = makeSnapshot(frameCount, elapsedSeconds, fs, frameLength, ...
        totalProcessTime, rollingValues, rollingCount, rollingIndex, ...
        totalOverrun, totalUnderrun, inputFrame, outputFrame, config, ioMode)
ordered = orderedRollingValues(rollingValues, rollingCount, rollingIndex);
if isempty(ordered)
    ordered = 0;
end
frameDuration = frameLength / fs;
meanProcess = totalProcessTime / max(frameCount, 1);
rollingMean = mean(ordered);
rollingP95 = percentileSimple(ordered, 95);

snapshot = struct();
snapshot.frameCount = frameCount;
snapshot.elapsedSeconds = elapsedSeconds;
snapshot.sampleRate = fs;
snapshot.frameLength = frameLength;
snapshot.frameDurationMs = 1000 * frameDuration;
snapshot.lastProcessMs = 1000 * ordered(end);
snapshot.meanProcessMs = 1000 * meanProcess;
snapshot.rollingMeanProcessMs = 1000 * rollingMean;
snapshot.p95ProcessMs = 1000 * rollingP95;
snapshot.maxProcessMs = 1000 * max(ordered);
snapshot.realtimeFactor = rollingMean / frameDuration;
snapshot.totalOverrunSamples = totalOverrun;
snapshot.totalUnderrunSamples = totalUnderrun;
snapshot.inputFrame = inputFrame;
snapshot.outputFrame = outputFrame;
snapshot.inputRmsDb = rmsDb(inputFrame);
snapshot.outputRmsDb = rmsDb(outputFrame);
snapshot.inputPeakDb = peakDb(inputFrame);
snapshot.outputPeakDb = peakDb(outputFrame);
snapshot.voiceMode = char(getConfigText(config.voice, {'type','mode'}, 'none'));
snapshot.fxMode = char(getConfigText(config.fx, {'type','mode'}, 'none'));
snapshot.spaceMode = char(getConfigText(config.space, {'type','mode'}, 'none'));
snapshot.ioMode = ioMode;
% This is a transparent internal budget indicator, not physical round-trip
% latency. Duplex has the explicit one-frame processing queue described above.
if strcmp(ioMode, 'duplex')
    queueFrames = 1;
else
    queueFrames = 2;
end
snapshot.nominalBufferBudgetMs = 1000 * (queueFrames * frameDuration + rollingMean);
end

function values = orderedRollingValues(buffer, count, lastIndex)
if count <= 0
    values = zeros(0, 1);
    return;
end
if count < numel(buffer)
    values = buffer(1:count);
    return;
end
startIndex = mod(lastIndex, numel(buffer)) + 1;
indices = [startIndex:numel(buffer), 1:startIndex-1];
values = buffer(indices);
end

function value = getConfigText(section, candidateFields, fallback)
value = fallback;
for k = 1:numel(candidateFields)
    name = candidateFields{k};
    if isstruct(section) && isfield(section, name) && ~isempty(section.(name))
        value = section.(name);
        return;
    end
end
end

function frame = forceFrameLength(frame, frameLength)
frame = double(frame);
if isempty(frame)
    frame = zeros(frameLength, 1);
elseif ~isvector(frame)
    frame = mean(frame, 2);
end
frame = frame(:);
frame(~isfinite(frame)) = 0;
if numel(frame) < frameLength
    frame(end+1:frameLength, 1) = 0;
elseif numel(frame) > frameLength
    frame = frame(1:frameLength);
end
end

function value = rmsDb(x)
x = double(x(:));
value = 20 * log10(max(sqrt(mean(x .^ 2)), 1e-8));
end

function value = peakDb(x)
x = double(x(:));
value = 20 * log10(max(max(abs(x)), 1e-8));
end

function validateDuration(value)
if ~isscalar(value) || isnan(value) || value <= 0
    error('runRealtimeVoiceChanger:InvalidDuration', ...
        'durationSeconds must be a positive scalar or Inf.');
end
end

function validateCallback(value, name)
if ~isempty(value) && ~isa(value, 'function_handle')
    error('runRealtimeVoiceChanger:InvalidCallback', ...
        '%s must be a function handle or empty.', name);
end
end

function value = getOpt(options, fieldName, defaultValue)
if isstruct(options) && isfield(options, fieldName) && ...
        ~isempty(options.(fieldName))
    value = options.(fieldName);
else
    value = defaultValue;
end
end

function text = canonicalText(value, fallback)
try
    text = strtrim(char(value));
catch
    text = fallback;
end
if isempty(text)
    text = fallback;
end
end

function value = positiveScalar(value, fallback)
value = double(value);
if isempty(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
    value = fallback;
end
end

function value = clampFinite(value, low, high, fallback)
value = double(value);
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = fallback;
end
value = min(max(value, low), high);
end

function tf = logicalScalar(value, fallback)
if islogical(value) || isnumeric(value)
    if isempty(value)
        tf = fallback;
    else
        tf = logical(value(1));
    end
    return;
end
try
    text = lower(strtrim(char(value)));
    tf = any(strcmp(text, {'true','on','yes','1'}));
catch
    tf = fallback;
end
end

function value = percentileSimple(x, p)
x = sort(x(:));
if isempty(x)
    value = NaN;
    return;
end
position = 1 + (numel(x)-1) * p / 100;
lo = floor(position);
hi = ceil(position);
if lo == hi
    value = x(lo);
else
    w = position - lo;
    value = (1-w) * x(lo) + w * x(hi);
end
end
