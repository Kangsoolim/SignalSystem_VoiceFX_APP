%TEST_21_NOISE_UPGRADE Validate upgraded reproducible noise scenarios.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1.5-1/fs).';
x = 0.22*sin(2*pi*220*t) + 0.09*sin(2*pi*440*t);
config = makeDefaultConfig();

types = {'white','pink','powerline_hum','impulse_keyboard','babble_crowd'};
for k = 1:numel(types)
    c = config.noise;
    c.enabled = true;
    c.type = types{k};
    c.mode = types{k};
    c.seed = 2026;
    c.snrDb = 12;
    c.whiteMode = 'snr';
    c.impulseProbability = 0.006;

    [y1, ~] = addNoise(x, fs, c, initProcessState(config));
    [y2, ~] = addNoise(x, fs, c, initProcessState(config));

    assert(numel(y1) == numel(x), 'Noise output length mismatch.');
    assert(all(isfinite(y1)), 'Noise output contains nonfinite samples.');
    assert(norm(y1-y2) < 1e-10, ...
        'Fixed seed should reproduce the same single-frame noise scenario.');

    n = y1-x;
    measuredSnr = 20*log10(rmsLocal(x)/max(rmsLocal(n), eps));
    assert(abs(measuredSnr-12) < 1.0, ...
        sprintf('%s SNR mismatch: %.2f dB.', types{k}, measuredSnr));
end

% Pink-like noise should concentrate more energy at low frequencies than
% white noise generated under the same SNR target.
c = config.noise; c.enabled = true; c.seed = 77; c.snrDb = 12; c.whiteMode = 'snr';
c.type = 'white';
[yWhite, ~] = addNoise(x, fs, c, initProcessState(config));
c.type = 'pink';
[yPink, ~] = addNoise(x, fs, c, initProcessState(config));
whiteRatio = lowHighRatio(yWhite-x, fs);
pinkRatio = lowHighRatio(yPink-x, fs);
assert(pinkRatio > whiteRatio, ...
    'Pink-like noise should have a larger low/high spectral ratio than white noise.');

disp('test_21_noise_upgrade passed: five upgraded noise scenarios are safe and reproducible.');

function value = rmsLocal(x)
value = sqrt(mean(double(x(:)).^2));
end
function ratio = lowHighRatio(x, fs)
x = double(x(:));
N = numel(x);
X = abs(fft(x));
f = (0:N-1)'*fs/N;
low = sum(X(f>=50 & f<=800).^2);
high = sum(X(f>=3000 & f<=7000).^2);
ratio = low/max(high, eps);
end
