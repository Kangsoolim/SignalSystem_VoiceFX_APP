%TEST_14_SPEECH_CLEAN_FILTER Validate causal speech-clean enhancement path.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:3-1/fs).';
clean = 0.22*sin(2*pi*180*t) + 0.11*sin(2*pi*360*t) + ...
    0.06*sin(2*pi*720*t) + 0.035*sin(2*pi*1450*t);
hum = 0.08*sin(2*pi*50*t) + 0.025*sin(2*pi*100*t);
rng(19, 'twister');
noisy = clean + hum + 0.025*randn(size(clean));

config = makeDefaultConfig();
config.audio.frameLength = 512;
config.filter.enabled = true;
config.filter.type = 'speech_clean';
config.filter.mode = 'speech_clean';

[y, state] = processAudioFile(noisy, fs, config);

assert(numel(y) == numel(noisy), 'speech_clean length must match input.');
assert(all(isfinite(y)), 'speech_clean output must be finite.');
assert(max(abs(y)) <= 1.000001, 'speech_clean output must be safe.');
assert(isfield(state.filter, 'speechClean'), ...
    'speech_clean must preserve cross-frame state.');

humBefore = toneMagnitude(noisy, fs, 50);
humAfter = toneMagnitude(y, fs, 50);
attenDb = 20*log10(max(humAfter,eps)/max(humBefore,eps));
assert(attenDb < -6, ...
    sprintf('speech_clean should reduce 50 Hz hum; got %.2f dB.', attenDb));

outRms = sqrt(mean(y.^2));
inRms = sqrt(mean(noisy.^2));
assert(outRms > 0.15*inRms && outRms < 1.3*inRms, ...
    'speech_clean should avoid collapse or uncontrolled gain.');

fprintf('speech_clean 50 Hz attenuation: %.2f dB\n', attenDb);
disp('test_14_speech_clean_filter passed: causal enhancement is stable.');

function value = toneMagnitude(x, fs, frequency)
x = double(x(:));
n = numel(x);
window = 0.5 - 0.5*cos(2*pi*(0:n-1).'/max(n-1,1));
X = abs(fft(x.*window));
bin = round(frequency/fs*n)+1;
bin = min(max(bin,1),n);
value = X(bin);
end
