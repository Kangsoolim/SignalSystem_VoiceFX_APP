%TEST_24_MODULE_SWITCHES Verify all course modules retain explicit switches.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeDefaultConfig();
moduleNames = {'noise', 'filter', 'voice', 'fx', 'space', ...
    'modDemod', 'display'};
for k = 1:numel(moduleNames)
    name = moduleNames{k};
    assert(isfield(config, name), ['Missing config module: ', name]);
    assert(isfield(config.(name), 'enabled'), ...
        ['Missing enabled switch for module: ', name]);
    assert(isscalar(config.(name).enabled), ...
        ['Enabled switch must be scalar for module: ', name]);
end

% Confirm switches are independently editable and do not alias each other.
config.noise.enabled = true;
config.filter.enabled = false;
config.voice.enabled = true;
config.fx.enabled = false;
config.space.enabled = true;
config.modDemod.enabled = false;
config.display.enabled = true;

assert(config.noise.enabled && ~config.filter.enabled);
assert(config.voice.enabled && ~config.fx.enabled);
assert(config.space.enabled && ~config.modDemod.enabled);
assert(config.display.enabled);

disp('test_24_module_switches passed: all course modules remain independently switchable.');
