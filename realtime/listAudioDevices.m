function devices = listAudioDevices()
%LISTAUDIODEVICES Print available realtime input/output device names.

if exist('audioDeviceReader', 'file') ~= 2 || ...
        exist('audioDeviceWriter', 'file') ~= 2
    error('listAudioDevices:AudioToolboxRequired', ...
        'Audio Toolbox device objects are not available.');
end

reader = audioDeviceReader;
writer = audioDeviceWriter;
cleanupObj = onCleanup(@()releaseDevices(reader, writer)); %#ok<NASGU>

inputDevices = getAudioDevices(reader);
outputDevices = getAudioDevices(writer);

devices = struct('input', {inputDevices}, 'output', {outputDevices});

disp('=== Input devices ===');
disp(inputDevices);
disp('=== Output devices ===');
disp(outputDevices);
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
