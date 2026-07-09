function fig = launchVoiceFXDashboard(varargin)
%LAUNCHVOICEFXDASHBOARD Add project paths and launch the VoiceFX Dashboard.
root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
fig = VoiceFXDashboard(varargin{:});
end
