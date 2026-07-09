function app = launchVoiceFXApp()
%LAUNCHVOICEFXAPP Start the VoiceFX programmatic UI App.
%   Run this from the project root or from the app/ folder.

thisFile = mfilename('fullpath');
appDir = fileparts(thisFile);
projectRoot = fileparts(appDir);

if exist(fullfile(projectRoot, 'core', 'makeDefaultConfig.m'), 'file') ~= 2
    if exist(fullfile(pwd, 'core', 'makeDefaultConfig.m'), 'file') == 2
        projectRoot = pwd;
    else
        error('launchVoiceFXApp:ProjectRootNotFound', 'Could not locate the VoiceFX project root.');
    end
end

addpath(fullfile(projectRoot, 'core'));
addpath(fullfile(projectRoot, 'modules'));
addpath(fullfile(projectRoot, 'app'));
realtimeDir = fullfile(projectRoot, 'realtime');
if exist(realtimeDir, 'dir') == 7
    addpath(realtimeDir);
end

app = VoiceFXApp(projectRoot);
end
