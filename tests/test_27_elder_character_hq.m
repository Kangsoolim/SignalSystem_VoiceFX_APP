%TEST_27_ELDER_CHARACTER_HQ Validate subtle continuous elder modulation.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:3-1/fs).';
x = 0.35*sin(2*pi*165*t) + 0.14*sin(2*pi*330*t) + ...
    0.06*sin(2*pi*660*t);
x = x .* (0.55 + 0.35*sin(2*pi*1.7*t).^2);

cfg = makeDefaultConfig();
v = cfg.voice;
v.params.elderTremorDepth = 0.018;
v.params.elderTremorRateHz = 4.8;
v.params.elderMicroDelayMs = 0.12;

[y, diag] = applyElderCharacterHQ(x, fs, v);
assert(numel(y) == numel(x), 'Elder character stage must preserve length.');
assert(all(isfinite(y)), 'Elder character stage must remain finite.');
assert(max(abs(y)) < 1.0, 'Elder character stage must remain bounded.');
assert(norm(y-x)/max(norm(x),eps) > 1e-4, ...
    'Enabled elder character stage should not collapse to identity.');
assert(diag.tremorDepth > 0 && diag.tremorDepth < 0.04, ...
    'Tremor depth must stay subtle and bounded.');

disp('test_27_elder_character_hq passed: continuous elder modulation is safe.');
