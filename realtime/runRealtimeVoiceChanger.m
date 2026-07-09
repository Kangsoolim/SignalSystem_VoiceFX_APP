function stats = runRealtimeVoiceChanger(durationSeconds, voiceMode, options)
%RUNREALTIMEVOICECHANGER Realtime microphone -> VoiceFX -> speaker loop.
%
%   stats = runRealtimeVoiceChanger(20, 'female')
%   stats = runRealtimeVoiceChanger(20, 'male', options)
%
% options fields (all optional):
%   sampleRate       default 48000
%   frameLength      default 512
%   inputDevice      default system device
%   outputDevice     default system device
%   intensity        default 0.62
%   enableSpeechClean default true
%
% Press Ctrl+C to stop early. The first calibration interval is intentionally
% mostly dry; the transformed signal fades in after a stable source profile
% is available.

if nargin < 1 || isempty(durationSeconds), durationSeconds = 20; end
if nargin < 2 || isempty(voiceMode), voiceMode = 'female'; end
if nargin < 3 || isempty(options), options = struct(); end

if exist('audioDeviceReader', 'file') ~= 2 || ...
        exist('audioDeviceWriter', 'file') ~= 2
    error('runRealtimeVoiceChanger:AudioToolboxRequired', ...
        'audioDeviceReader/audioDeviceWriter are required.');
end

fs = getOpt(options, 'sampleRate', 48000);
frameLength = round(getOpt(options, 'frameLength', 512));
intensity = getOpt(options, 'intensity', 0.62);
enableSpeechClean = logical(getOpt(options, 'enableSpeechClean', true));

readerArgs = {'SampleRate', fs, 'SamplesPerFrame', frameLength, ...
    'NumChannels', 1};
inputDevice = getOpt(options, 'inputDevice', '');
if ~isempty(inputDevice)
    readerArgs = [readerArgs, {'Device', char(inputDevice)}]; %#ok<AGROW>
end
reader = audioDeviceReader(readerArgs{:});

writerArgs = {'SampleRate', fs};
outputDevice = getOpt(options, 'outputDevice', '');
if ~isempty(outputDevice)
    writerArgs = [writerArgs, {'Device', char(outputDevice)}]; %#ok<AGROW>
end
writer = audioDeviceWriter(writerArgs{:});

cleanupObj = onCleanup(@()releaseDevices(reader, writer)); %#ok<NASGU>
setup(reader);
setup(writer, zeros(frameLength, 1));

config = makeDefaultConfig();
config.audio.frameLength = frameLength;
config.audio.normalizeInput = false;
config.audio.removeDC = false;
config.filter.enabled = enableSpeechClean;
if enableSpeechClean
    config.filter.type = 'speech_clean';
    config.filter.mode = 'speech_clean';
end
config.voice.enabled = true;
config.voice.type = char(voiceMode);
config.voice.mode = char(voiceMode);
config.voice.mix = 1.0;
config.voice.intensity = intensity;
config.voice.params.adaptiveEnabled = true;
config.voice.params.calibrationSeconds = 0.80;
config.output.limiterMode = 'soft';

state = initProcessState(config);

totalOverrun = 0;
totalUnderrun = 0;
frameCount = 0;
processTimes = zeros(max(100, ceil(durationSeconds*fs/frameLength)+10), 1);

fprintf('Realtime voice changer started: mode=%s, fs=%g, frame=%d\n', ...
    char(voiceMode), fs, frameLength);
fprintf('The first %.2f s are used for calibration. Press Ctrl+C to stop.\n', ...
    config.voice.params.calibrationSeconds);

startTime = tic;
while toc(startTime) < durationSeconds
    [xFrame, overrun] = reader();
    frameTic = tic;
    [yFrame, state] = processAudioFrame(xFrame, fs, config, state);
    processElapsed = toc(frameTic);
    underrun = writer(yFrame);

    frameCount = frameCount + 1;
    if frameCount > numel(processTimes)
        processTimes = [processTimes; zeros(1000,1)]; %#ok<AGROW>
    end
    processTimes(frameCount) = processElapsed;
    totalOverrun = totalOverrun + double(overrun);
    totalUnderrun = totalUnderrun + double(underrun);
end

processTimes = processTimes(1:frameCount);
frameDuration = frameLength/fs;
stats = struct();
stats.voiceMode = char(voiceMode);
stats.sampleRate = fs;
stats.frameLength = frameLength;
stats.frameDurationMs = 1000*frameDuration;
stats.framesProcessed = frameCount;
stats.totalOverrunSamples = totalOverrun;
stats.totalUnderrunSamples = totalUnderrun;
stats.meanProcessMs = 1000*mean(processTimes);
stats.p95ProcessMs = 1000*percentileSimple(processTimes, 95);
stats.maxProcessMs = 1000*max(processTimes);
stats.meanRealtimeFactor = mean(processTimes)/frameDuration;
stats.finalState = state;

fprintf('\nRealtime session finished.\n');
fprintf('  Mean processing: %.2f ms/frame\n', stats.meanProcessMs);
fprintf('  P95 processing : %.2f ms/frame\n', stats.p95ProcessMs);
fprintf('  Mean RTF       : %.3f\n', stats.meanRealtimeFactor);
fprintf('  Overrun samples: %d\n', totalOverrun);
fprintf('  Underrun samples: %d\n', totalUnderrun);
end

function value = getOpt(options, fieldName, defaultValue)
if isstruct(options) && isfield(options, fieldName) && ...
        ~isempty(options.(fieldName))
    value = options.(fieldName);
else
    value = defaultValue;
end
end

function releaseDevices(reader, writer)
try
    release(reader);
catch
end
try
    release(writer);
catch
end
end

function value = percentileSimple(x, p)
x = sort(x(:));
if isempty(x)
    value = NaN;
    return;
end
position = 1 + (numel(x)-1)*p/100;
lo = floor(position);
hi = ceil(position);
if lo == hi
    value = x(lo);
else
    w = position-lo;
    value = (1-w)*x(lo)+w*x(hi);
end
end
