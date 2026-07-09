%TEST_20_VAD_AWARE_DENOISE Validate VAD-aware speech_clean behavior.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
duration = 4.0;
t = (0:1/fs:duration-1/fs).';
clean = zeros(size(t));
mask = (t >= 0.7 & t < 1.7) | (t >= 2.2 & t < 3.4);
phase = cumsum(2*pi*(165 + 8*sin(2*pi*1.0*t))/fs);
speech = 0.27*sin(phase) + 0.12*sin(2*phase) + 0.06*sin(3*phase);
clean(mask) = speech(mask);

rng(33, 'twister');
noise = 0.055*randn(size(clean));
noisy = clean + noise;

config = makeDefaultConfig();
config.audio.frameLength = 512;
config.filter.enabled = true;
config.filter.type = 'speech_clean';
config.filter.mode = 'speech_clean';
config.filter.noiseReductionStrength = 0.80;

[y, state] = processAudioFile(noisy, fs, config);
assert(numel(y) == numel(noisy), 'Denoise output length mismatch.');
assert(all(isfinite(y)), 'Denoise output contains nonfinite samples.');
assert(max(abs(y)) <= 1.000001, 'Denoise output exceeds safe range.');
assert(isfield(state.filter, 'vadSpeechProbability'), ...
    'VAD speech probability must be exposed in filter state.');
assert(state.filter.vadSpeechProbability >= 0 && ...
    state.filter.vadSpeechProbability <= 1, ...
    'VAD speech probability must be bounded.');

noiseMask = ~mask;
noiseBefore = sqrt(mean(noisy(noiseMask).^2));
noiseAfter = sqrt(mean(y(noiseMask).^2));
assert(noiseAfter < 0.92*noiseBefore, ...
    'VAD-aware enhancer should reduce noise-only RMS.');

speechIdx = find(mask);
corrValue = normalizedCorrelation(clean(speechIdx), y(speechIdx));
assert(corrValue > 0.65, ...
    'Speech region should retain useful waveform correlation.');

fprintf('Noise-only RMS before %.5f, after %.5f; speech corr %.3f\n', ...
    noiseBefore, noiseAfter, corrValue);
disp('test_20_vad_aware_denoise passed: VAD-aware enhancement is bounded and speech-preserving.');

function value = normalizedCorrelation(a, b)
a = double(a(:)); b = double(b(:));
a = a-mean(a); b = b-mean(b);
value = (a'*b) / max(norm(a)*norm(b), eps);
end
