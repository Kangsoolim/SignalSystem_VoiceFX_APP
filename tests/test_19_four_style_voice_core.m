%TEST_19_FOUR_STYLE_VOICE_CORE Validate four natural adaptive styles.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2.2-1/fs).';
f0 = 150 .* (1 + 0.035*sin(2*pi*1.1*t));
phase = cumsum(2*pi*f0/fs);
env = 0.42 + 0.34*sin(2*pi*2.2*t).^2;
x = env .* (0.31*sin(phase) + 0.15*sin(2*phase) + ...
    0.08*sin(3*phase) + 0.035*sin(5*phase));
x = x + 0.028*sin(2*pi*760*t) + 0.018*sin(2*pi*1480*t);
x = 0.55*x/max(abs(x));

profile = analyzeVoiceProfile(x, fs);
assert(strcmp(profile.status,'ok'), 'Synthetic source profile must be voiced.');

styles = {'male_deep_gentle','female_gentle_sweet', ...
    'child_bright_soft','elder_warm_steady'};
outputs = cell(size(styles));
shifts = zeros(size(styles));
formantScales = zeros(size(styles));
envelopeStrengths = zeros(size(styles));

for k = 1:numel(styles)
    config = makeDefaultConfig();
    config.audio.frameLength = 512;
    config.voice.enabled = true;
    config.voice.type = styles{k};
    config.voice.mode = styles{k};
    config.voice.mix = 1.0;
    config.voice.intensity = 0.70;
    config.voice.params.sourceProfile = profile;

    [y, state] = processAudioFile(x, fs, config);
    assert(numel(y) == numel(x), 'Style output length mismatch.');
    assert(all(isfinite(y)), 'Style output contains nonfinite samples.');
    assert(max(abs(y)) <= 1.000001, 'Style output exceeds safe range.');
    assert(isfield(state.voice,'adaptiveConfig'), ...
        'Adaptive config must be stored in state.');

    outputs{k} = y;
    shifts(k) = state.voice.adaptiveConfig.pitchShift;
    formantScales(k) = state.voice.adaptiveConfig.params.formantScale;
    envelopeStrengths(k) = ...
        state.voice.adaptiveConfig.params.envelopeWarpStrength;
end

% For a 150 Hz source, male and elder may intentionally keep pitch close to
% the source because it already lies inside both broad style regions.
assert(shifts(2) > shifts(1), ...
    'Female mapping should move higher than male mapping for this source.');
assert(shifts(3) > shifts(2), ...
    'Child mapping should move higher than female mapping.');
assert(formantScales(1) < 1, ...
    'Male envelope direction should be gently downward.');
assert(formantScales(2) > 1, ...
    'Female envelope direction should be gently upward.');
assert(formantScales(3) > formantScales(2), ...
    'Child envelope direction should exceed female direction.');
assert(formantScales(4) <= 1, ...
    'Elder envelope direction should be neutral-to-downward.');
assert(all(envelopeStrengths >= 0 & envelopeStrengths <= 0.5), ...
    'Natural envelope shaping must remain mild.');

for a = 1:numel(outputs)
    for b = a+1:numel(outputs)
        relativeDifference = norm(outputs{a}-outputs{b}) / max(norm(x),eps);
        assert(relativeDifference > 1e-4, ...
            'Different styles must not collapse to identical outputs.');
    end
end

fprintf('Pitch shifts [male female child elder] = [%.2f %.2f %.2f %.2f] st\n', ...
    shifts(1), shifts(2), shifts(3), shifts(4));
fprintf('Formant scales = [%.3f %.3f %.3f %.3f]\n', ...
    formantScales(1), formantScales(2), formantScales(3), formantScales(4));
disp('test_19_four_style_voice_core passed: four natural styles are distinct and safe.');
