function inputPath = resolveVoiceTestInput(inputArg, projectRoot)
%RESOLVEVOICETESTINPUT Resolve an input path or a filename in ../Voice_test.
%
%   inputPath = resolveVoiceTestInput(inputArg, projectRoot)
%
%   Accepted input forms:
%       'D:\Projects\Voice_test\sample.wav'
%       'sample.wav'
%
%   A bare filename is resolved against the sibling folder:
%       <parent-of-project>/Voice_test/

if nargin < 2 || isempty(projectRoot)
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(thisFile));
end
if nargin < 1 || isempty(inputArg)
    error('resolveVoiceTestInput:MissingInput', ...
        'Provide an audio path or a filename located in the Voice_test folder.');
end

inputArg = char(inputArg);

% Direct path first. exist() also accepts relative paths from pwd.
if exist(inputArg, 'file') == 2
    inputPath = absolutePath(inputArg);
    return;
end

voiceTestDir = fullfile(fileparts(projectRoot), 'Voice_test');
candidate = fullfile(voiceTestDir, inputArg);
if exist(candidate, 'file') == 2
    inputPath = candidate;
    return;
end

error('resolveVoiceTestInput:InputNotFound', ...
    ['Audio file not found. Checked direct path and Voice_test folder:\n', ...
     '  %s\n  %s'], inputArg, candidate);
end

function pathOut = absolutePath(pathIn)
pathIn = char(pathIn);
if ispc
    isAbsolute = numel(pathIn) >= 3 && pathIn(2) == ':' && ...
        any(pathIn(3) == ['\', '/']);
else
    isAbsolute = startsWith(pathIn, filesep);
end
if isAbsolute
    pathOut = pathIn;
else
    pathOut = fullfile(pwd, pathIn);
end
end
