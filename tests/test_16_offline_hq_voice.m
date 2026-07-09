%TEST_16_OFFLINE_HQ_VOICE Validate full-utterance high-quality voice path.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.5-1/fs).';
f0 = 135 + 9*sin(2*pi*0.8*t);
phase = cumsum(2*pi*f0/fs);
x = 0.32*sin(phase) + 0.15*sin(2*phase) + 0.07*sin(3*phase);
x = 0.6*x/max(abs(x));

config = makeDefaultConfig();
config.filter.enabled = true;
config.filter.type = 'speech_clean';
config.filter.mode = 'speech_clean';
config.voice.enabled = true;
config.voice.type = 'female';
config.voice.mode = 'female';
config.voice.intensity = 0.62;
config.voice.pitchShift = 0;

[y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);

assert(numel(y) == numel(x), 'HQ output length must equal input length.');
assert(iscolumn(y), 'HQ output must be a column vector.');
assert(all(isfinite(y)), 'HQ output must contain only finite samples.');
assert(max(abs(y)) <= config.output.peakLimit + 1e-6, ...
    'HQ output must respect configured peak limit.');
assert(isstruct(state), 'State output must be a struct.');
assert(strcmp(diagnostics.status, 'ok'), 'HQ diagnostics status must be ok.');
assert(isfield(diagnostics.voice, 'adaptive'), ...
    'HQ diagnostics must include adaptive mapping information.');

maleConfig = config;
maleConfig.voice.type = 'male';
maleConfig.voice.mode = 'male';
[maleY, ~, maleDiag] = processAudioFileHighQuality(x, fs, maleConfig);
assert(numel(maleY) == numel(x) && all(isfinite(maleY)), ...
    'HQ male output must remain safe.');
assert(maleDiag.voice.adaptive.recommendedPitchShift < -1.2, ...
    'HQ male must keep an audible downward/source-masculine shift.');
assert(maleDiag.voice.adaptive.formantScale < 0.97, ...
    'HQ male must apply an audible but bounded formant direction.');

childConfig = config;
childConfig.voice.type = 'child';
childConfig.voice.mode = 'child';
[childY, ~, childDiag] = processAudioFileHighQuality(x, fs, childConfig);
assert(numel(childY) == numel(x) && all(isfinite(childY)), ...
    'HQ child output must remain safe.');
assert(childDiag.voice.adaptive.recommendedPitchShift < 8.2, ...
    'HQ child pitch lift should stay below the harsh/telephone range.');
assert(childDiag.voice.adaptive.formantScale <= 1.15, ...
    'HQ child formant lift should remain bounded to reduce electric artifacts.');

highRatio = highBandRatio(childY, fs) / max(highBandRatio(x, fs), eps);
assert(highRatio < 2.6, ...
    'HQ child should not create excessive high-frequency harshness.');

disp('test_16_offline_hq_voice passed: full-utterance HQ path is numerically safe and audible.');

function ratio = highBandRatio(x, fs)
x = double(x(:));
n = numel(x);
if n == 0
    ratio = 0;
    return;
end
idx = (0:n-1).';
w = 0.5 - 0.5*cos(2*pi*idx/max(n-1,1));
mag = abs(fft(x.*w));
count = floor(n/2)+1;
mag = mag(1:count).^2;
freq = (0:count-1).'*fs/n;
ratio = sum(mag(freq >= 4200)) / max(sum(mag), eps);
end
