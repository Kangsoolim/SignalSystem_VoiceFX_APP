%TEST_SPACE_PRESETS Validate curated M07 space presets and frame continuity.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2.4-1/fs).';
env = min(1, t / 0.08) .* exp(-0.08 * t);
x = env .* (0.30 * sin(2 * pi * 180 * t) + ...
    0.16 * sin(2 * pi * 520 * t) + ...
    0.08 * sin(2 * pi * 1450 * t));
x = x(:);

config = makeDefaultConfig();
assert(isfield(config.space, 'presets'), 'Space presets must be defined.');
assert(isequal(config.space.displayPresets, {'delay', 'bathroom'}), 'Display presets should be delay/bathroom.');
assert(isequal(config.space.hiddenPresets, {'cave'}), 'Only cave should be hidden by default.');
assert(config.space.presets.bathroom.showInApp, 'Bathroom should be kept as a display preset.');
assert(~isfield(config.space.presets, 'reverb') && ~isfield(config.space.presets, 'stage'), 'Reverb and stage presets should be removed.');
assert(~config.space.presets.cave.showInApp, 'Cave should be retained but hidden.');
assert(config.space.feedback <= 0.35, 'Default feedback should stay controlled.');
assert(config.space.reverbAmount <= 0.50, 'Default reverb amount should stay controlled.');

modes = {'delay', 'bathroom', 'cave'};
for k = 1:numel(modes)
    cfg = config.space;
    cfg.enabled = true;
    cfg.type = modes{k};

    [singleY, singleState] = applySpaceFX(x, fs, cfg, initProcessState(config));
    [framedY, framedState] = processInFrames(x, fs, cfg, config);

    assert(isstruct(singleState) && isstruct(framedState), 'Space processing must return state structs.');
    assert(isfield(framedState, 'space'), 'Frame state must include state.space.');
    assert(numel(singleY) == numel(x) && numel(framedY) == numel(x), 'Space output length must match input.');
    assert(iscolumn(singleY) && iscolumn(framedY), 'Space output must be column vectors.');
    assert(all(isfinite(singleY)) && all(isfinite(framedY)), 'Space output must be finite.');
    assert(max(abs(singleY)) <= 1.000001 && max(abs(framedY)) <= 1.000001, 'Space output must stay in limiter range.');

    continuityDiff = max(abs(singleY - framedY));
    assert(continuityDiff < 1e-10, 'Frame processing must match single-pass processing without restarting state.space.');

    if strcmp(modes{k}, 'delay')
        assert(isfield(framedState.space, 'delayBuffer') && isfield(framedState.space, 'delayIndex'), 'Delay must persist state.space delay buffer/index.');
    else
        assert(isfield(framedState.space, 'reverbBuffers') && isfield(framedState.space, 'reverbIndices'), 'Reverb-style modes must persist state.space buffers/indices.');
    end

    diffRms = rmsLocal(framedY - x);
    dryRms = max(rmsLocal(x), eps);
    diffRatio = diffRms / dryRms;
    if any(strcmp(modes{k}, {'bathroom', 'cave'}))
        assert(diffRatio > 0.18, 'Reverb-style space presets should be clearly audible versus dry input.');
    end
    if strcmp(modes{k}, 'bathroom')
        assert(diffRatio < 0.85, 'Display space presets should stay intelligible.');
    elseif strcmp(modes{k}, 'cave')
        assert(diffRatio < 1.15, 'Hidden audition presets should avoid excessive wash or runaway tails.');
    end
end

stressCfg = config.space;
stressCfg.enabled = true;
stressCfg.type = 'delay';
stressCfg.feedback = 0.95;
stressCfg.mix = 0.45;
stressCfg.delayTime = 0.11;
impulse = [0.95; zeros(round(4 * fs), 1)];
[stressY, stressState] = applySpaceFX(impulse, fs, stressCfg, initProcessState(config));
assert(isfield(stressState.space, 'delayBuffer'), 'Delay stress test must use state.space delay buffer.');
assert(all(isfinite(stressY)), 'High feedback delay output must stay finite.');
assert(max(abs(stressY)) <= 1.000001, 'High feedback delay output must not explode.');
assert(rmsLocal(stressY(end - round(0.5 * fs):end)) < 0.02, 'Delay feedback tail should decay instead of sustaining blast-level echoes.');

legacyCfg = config.space;
legacyCfg.enabled = true;
legacyCfg.type = 'stage';
[legacyY, legacyState] = applySpaceFX(x, fs, legacyCfg, initProcessState(config));
bathroomCfg = config.space;
bathroomCfg.enabled = true;
bathroomCfg.type = 'bathroom';
[bathroomY, ~] = applySpaceFX(x, fs, bathroomCfg, initProcessState(config));
assert(max(abs(legacyY - bathroomY)) < 1e-10, 'Legacy stage should resolve to the new bathroom effect.');
assert(strcmp(legacyState.space.lastMode, 'bathroom'), 'Legacy stage should be recorded as bathroom in state.space.');

disp('test_space_presets passed: curated M07 space presets are stable and frame-continuous.');

function [y, state] = processInFrames(x, fs, spaceConfig, config)
state = initProcessState(config);
y = zeros(size(x));
frameSizes = [337, 1024, 511, 2048, 733];
startIndex = 1;
frameIndex = 1;
while startIndex <= numel(x)
    frameLength = frameSizes(1 + mod(frameIndex - 1, numel(frameSizes)));
    stopIndex = min(numel(x), startIndex + frameLength - 1);
    [frameY, state] = applySpaceFX(x(startIndex:stopIndex), fs, spaceConfig, state);
    y(startIndex:stopIndex) = frameY;
    startIndex = stopIndex + 1;
    frameIndex = frameIndex + 1;
end
end

function value = rmsLocal(x)
x = double(x(:));
value = sqrt(mean(x .^ 2));
end
