function devices = listAudioDevices(verbose)
%LISTAUDIODEVICES Return available split and full-duplex audio devices.
%   DEVICES = LISTAUDIODEVICES() also prints discovered device names.
%   DEVICES = LISTAUDIODEVICES(FALSE) stays quiet for Dashboard refresh.

if nargin < 1 || isempty(verbose)
    verbose = true;
end
if isempty(which('audioDeviceReader')) || ...
        isempty(which('audioDeviceWriter'))
    error('listAudioDevices:AudioToolboxRequired', ...
        'Audio Toolbox audio device objects are not available.');
end

reader = audioDeviceReader;
writer = audioDeviceWriter;
cleanupObj = onCleanup(@()releaseObjects(reader, writer, [])); %#ok<NASGU>
inputDevices = getAudioDevices(reader);
outputDevices = getAudioDevices(writer);

duplexDevices = {};
if ~isempty(which('audioPlayerRecorder'))
    try
        duplex = audioPlayerRecorder;
        duplexCleanup = onCleanup(@()releaseOne(duplex)); %#ok<NASGU>
        duplexDevices = getAudioDevices(duplex);
    catch
        % Some systems have Audio Toolbox but no compatible full-duplex
        % default device. Split input/output discovery should still succeed.
        duplexDevices = {};
    end
end

devices = struct('input', {normalizeDeviceList(inputDevices)}, ...
    'output', {normalizeDeviceList(outputDevices)}, ...
    'duplex', {normalizeDeviceList(duplexDevices)});

if verbose
    disp('=== Input devices ===');
    disp(devices.input);
    disp('=== Output devices ===');
    disp(devices.output);
    if ~isempty(devices.duplex)
        disp('=== Full-duplex devices ===');
        disp(devices.duplex);
    end
end
end

function values = normalizeDeviceList(values)
if isempty(values)
    values = {};
elseif iscell(values)
    values = cellfun(@char, values, 'UniformOutput', false);
elseif isstring(values)
    values = cellstr(values(:));
elseif ischar(values)
    values = cellstr(values);
else
    values = cellstr(string(values));
end
end

function releaseObjects(reader, writer, duplex)
releaseOne(reader);
releaseOne(writer);
releaseOne(duplex);
end

function releaseOne(object)
if isempty(object)
    return;
end
try
    release(object);
catch
end
end
