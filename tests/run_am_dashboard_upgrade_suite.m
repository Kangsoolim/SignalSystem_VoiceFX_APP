%RUN_AM_DASHBOARD_UPGRADE_SUITE Focused regression suite for the upgrade.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fprintf('\n=== VoiceFX AM / Dashboard / Realtime upgrade suite ===\n');
run(fullfile(projectRoot, 'tests', 'test_04_mod_demod.m'));
run(fullfile(projectRoot, 'tests', 'test_30_am_lab_core.m'));
run(fullfile(projectRoot, 'tests', 'test_31_dashboard_config_core.m'));
run(fullfile(projectRoot, 'tests', 'test_32_dashboard_ui_construction.m'));
fprintf('=== Upgrade suite complete ===\n');
