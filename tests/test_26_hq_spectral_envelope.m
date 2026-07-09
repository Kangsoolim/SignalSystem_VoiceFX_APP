%TEST_26_HQ_SPECTRAL_ENVELOPE Validate offline cepstral envelope warp safety.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2.5-1/fs).';
f0 = 170 + 6*sin(2*pi*0.8*t);
phase = cumsum(2*pi*f0/fs);

% Deterministic vowel-like harmonic source with broad resonant color.
x = 0.30*sin(phase) + 0.18*sin(2*phase) + 0.10*sin(3*phase) + ...
    0.06*sin(5*phase) + 0.035*sin(8*phase);
x = x .* (0.75 + 0.20*sin(2*pi*2.1*t).^2);
x = 0.6*x/max(abs(x));

base = makeDefaultConfig();
upCfg = base.voice;
upCfg.params.formantScale = 1.24;
upCfg.params.envelopeWarpStrength = 0.90;
upCfg.params.envelopeWarpMaxGainDb = 5.5;
upCfg.params.hqCepstralOrder = 34;

[yUp, diagUp] = warpSpectralEnvelopeHQ(x, fs, upCfg);
assert(numel(yUp) == numel(x), 'HQ warp must preserve length.');
assert(all(isfinite(yUp)), 'HQ warp must remain finite.');
assert(max(abs(yUp)) < 2.0, 'HQ warp must remain bounded before limiter.');
assert(diagUp.maxAbsoluteGainDb > 0.01, ...
    'Upward envelope warp should apply nonzero gain shaping.');
assert(norm(yUp-x)/max(norm(x),eps) > 1e-3, ...
    'Upward envelope warp must not collapse to identity.');

downCfg = upCfg;
downCfg.params.formantScale = 0.88;
downCfg.params.envelopeWarpStrength = 0.78;
[yDown, diagDown] = warpSpectralEnvelopeHQ(x, fs, downCfg);
assert(numel(yDown) == numel(x), 'Downward HQ warp must preserve length.');
assert(all(isfinite(yDown)), 'Downward HQ warp must remain finite.');
assert(diagDown.maxAbsoluteGainDb > 0.01, ...
    'Downward envelope warp should apply nonzero gain shaping.');
assert(norm(yDown-yUp)/max(norm(x),eps) > 1e-3, ...
    'Upward and downward envelope warps must be distinct.');

disp('test_26_hq_spectral_envelope passed: offline envelope warp is finite, bounded and directional.');
