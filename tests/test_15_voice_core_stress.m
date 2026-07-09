%TEST_15_VOICE_CORE_STRESS Exercise all voice modes and awkward frame sizes.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2.4-1/fs).';
f0 = 150 .* (1 + 0.04*sin(2*pi*1.2*t));
phase = cumsum(2*pi*f0/fs);
env = 0.45 + 0.35*sin(2*pi*2.4*t).^2;
x = env .* (0.30*sin(phase) + 0.13*sin(2*phase) + ...
    0.07*sin(3*phase) + 0.025*sin(2*pi*1700*t));
x = 0.60*x/max(abs(x));

modes = {'male','female','child','elder','anonymous','robot_voice'};
frameLengths = [257, 512, 1024];
profile = analyzeVoiceProfile(x, fs);

for f = 1:numel(frameLengths)
    for m = 1:numel(modes)
        config = makeDefaultConfig();
        config.audio.frameLength = frameLengths(f);
        config.filter.enabled = true;
        config.filter.type = 'speech_clean';
        config.voice.enabled = true;
        config.voice.type = modes{m};
        config.voice.mode = modes{m};
        config.voice.intensity = 0.60;
        config.voice.mix = 1.0;
        config.voice.params.sourceProfile = profile;

        [y, state] = processAudioFile(x, fs, config);
        assert(numel(y) == numel(x), 'Stress output length mismatch.');
        assert(all(isfinite(y)), 'Stress output contains nonfinite samples.');
        assert(max(abs(y)) <= 1.000001, 'Stress output exceeds safe range.');
        assert(isfield(state.voice, 'lastMode'), ...
            'Voice state should record last mode.');
    end
end

disp('test_15_voice_core_stress passed: modes and frame sizes are stable.');
