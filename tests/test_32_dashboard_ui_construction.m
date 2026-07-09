%TEST_32_DASHBOARD_UI_CONSTRUCTION Construct the programmatic UI when desktop is available.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if ~usejava('desktop')
    disp('test_32_dashboard_ui_construction skipped: MATLAB desktop is unavailable.');
    return;
end

fig = launchVoiceFXDashboard('Visible', 'off');
cleanupObj = onCleanup(@()closeFigureSafe(fig)); %#ok<NASGU>
drawnow;
assert(isvalid(fig), 'Dashboard figure should be valid after construction.');
assert(strcmp(fig.Name, 'VoiceFX Control Center'), 'Unexpected Dashboard figure name.');

tabs = findall(fig, 'Type', 'uitab');
assert(numel(tabs) == 3, 'Dashboard should contain exactly three workspace tabs.');

delete(fig);
fig = [];
disp('test_32_dashboard_ui_construction passed: Dashboard UI constructs successfully.');

function closeFigureSafe(fig)
if ~isempty(fig)
    try
        if isvalid(fig)
            delete(fig);
        end
    catch
    end
end
end
