%TEST_GRAMOPHONE_CANDIDATES Validate the finalized gramophone preset.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

config = makeDefaultConfig();
candidateIds = config.fx.gramophoneCandidatePresets;
rejectedIds = {'gramophone_classic', 'gramophone_obvious', ...
    'gramophone_noisy', 'gramophone_worn', 'vinyl_warble'};

assert(strcmp(config.fx.gramophoneOfficialPreset, 'gramophone'), ...
    'Official gramophone mode must be gramophone.');
assert(isequal(candidateIds, {'gramophone'}), ...
    'Default gramophone export list should contain only the official mode.');
assert(isfield(config.fx.presets, 'gramophone'), 'Official gramophone preset is missing.');
assert(isfield(config.fx.presets, 'gramophone_horn'), 'Internal gramophone_horn alias is missing.');
assert(config.fx.presets.gramophone.showInApp, 'Official gramophone should remain showable.');
assert(~config.fx.presets.gramophone_horn.showInApp, 'gramophone_horn should stay an internal alias.');
assert(strcmp(config.fx.presets.gramophone.displayName, char([32769 24335 30041 22768 26426])), ...
    'Official gramophone display name should be Chinese 老式留声机.');

for k = 1:numel(rejectedIds)
    rejectedId = rejectedIds{k};
    assert(~ismember(rejectedId, candidateIds), 'Rejected gramophone candidate leaked into export list.');
    assert(ismember(rejectedId, config.fx.deprecatedPresets), 'Rejected gramophone candidate should be deprecated.');
    assert(ismember(rejectedId, config.fx.hiddenPresets), 'Rejected gramophone candidate should be hidden.');
    assert(~isfield(config.fx.presets, rejectedId), 'Rejected gramophone candidate should not remain a preset.');
end

samplePath = pickRealSample(fullfile(projectRoot, 'samples'));
[xRaw, fs] = audioread(samplePath);
auditionConfig = makeAuditionConfig();
x = preprocessAudio(xRaw, fs, auditionConfig);
x = limitDuration(x, fs, 3.0);
x = safeLimiter(x, auditionConfig);

yOfficial = runFxMode(x, fs, config, 'gramophone');
yAlias = runFxMode(x, fs, config, 'gramophone_horn');

assert(numel(yOfficial) == numel(x), 'Gramophone output length must match input.');
assert(isa(yOfficial, 'double') && iscolumn(yOfficial), 'Gramophone output must be a double column vector.');
assert(all(isfinite(yOfficial)), 'Gramophone output must not contain NaN/Inf.');
assert(max(abs(yOfficial)) <= 1.000001, 'Gramophone output must stay inside [-1, 1].');
assert(rmsValue(yOfficial) > 0.04 * max(rmsValue(x), eps), 'Gramophone must not collapse to silence.');
assert(max(abs(yOfficial - yAlias)) < 1e-10, 'gramophone_horn alias should match official gramophone output.');

otherModes = {'telephone', 'radio', 'bitcrusher', 'robot'};
for k = 1:numel(otherModes)
    y = runFxMode(x, fs, config, otherModes{k});
    assert(numel(y) == numel(x), 'Existing FX output length must remain valid.');
    assert(isa(y, 'double') && iscolumn(y), 'Existing FX output must remain a double column vector.');
    assert(all(isfinite(y)), 'Existing FX output must remain finite.');
    assert(max(abs(y)) <= 1.000001, 'Existing FX output must remain limited.');
end

scriptText = fileread(fullfile(projectRoot, 'scripts', 'export_gramophone_candidates.m'));
assert(~isempty(strfind(scriptText, 'gramophoneOfficialPreset')), ...
    'Focused export script should use the official gramophone preset.');
assert(isempty(strfind(scriptText, 'gramophone_obvious')), ...
    'Focused export script must not export gramophone_obvious.');
assert(isempty(strfind(scriptText, 'gramophone_noisy')), ...
    'Focused export script must not export gramophone_noisy.');
assert(isempty(strfind(scriptText, 'gramophone_worn')), ...
    'Focused export script must not export gramophone_worn.');
assert(isempty(strfind(scriptText, 'vinyl_warble')), ...
    'Focused export script must not export vinyl_warble.');

disp('test_gramophone_candidates passed: official gramophone is finalized and bounded.');

function y = runFxMode(x, fs, config, mode)
fxConfig = config.fx;
fxConfig.enabled = true;
fxConfig.type = mode;
fxConfig.mode = 'legacy_value_should_not_override_type';
[y, ~] = applyVocalFX(x, fs, fxConfig, initProcessState(config));
end

function samplePath = pickRealSample(samplesDir)
preferred = dir(fullfile(samplesDir, '*spoken*.wav'));
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*upbeat*.wav'));
end
if isempty(preferred)
    preferred = dir(fullfile(samplesDir, '*.wav'));
end
assert(~isempty(preferred), 'At least one real wav sample is required under samples/.');
samplePath = fullfile(preferred(1).folder, preferred(1).name);
end

function config = makeAuditionConfig()
config = makeDefaultConfig();
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.82;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
end

function y = limitDuration(x, fs, maxSeconds)
x = x(:);
y = x(1:min(numel(x), max(1, round(maxSeconds * fs))));
end

function value = rmsValue(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end
