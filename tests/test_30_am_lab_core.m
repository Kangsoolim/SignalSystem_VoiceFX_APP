%TEST_30_AM_LAB_CORE Validate complete AM Lab experiment and mismatch response.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 48000;
t = (0:1/fs:1.5-1/fs).';
x = 0.55*sin(2*pi*320*t) + 0.25*sin(2*pi*910*t) + 0.08*sin(2*pi*1450*t);

options = struct();
options.carrierFreq = 8000;
options.modulationIndex = 0.70;
options.messageScale = 0.80;
options.lowpassCutoff = 2200;
options.filterOrder = 4;
options.channelSnrDb = 60;
options.receiverFreqOffsetHz = 0;
options.receiverPhaseOffsetDeg = 0;
options.experimentSeed = 11;

ideal = runAMExperiment(x, fs, options);
assert(numel(ideal.modulated) == numel(x), 'AM Lab must preserve sample count.');
assert(numel(ideal.demodulated) == numel(x), 'Recovered signal length must match input.');
assert(all(isfinite(ideal.modulated)) && all(isfinite(ideal.demodulated)), ...
    'AM Lab outputs must be finite.');
assert(ideal.metrics.correlation > 0.85, ...
    'Matched coherent receiver should retain strong waveform correlation.');
assert(ideal.metrics.reconstructionSnrDb > 6, ...
    'Matched coherent receiver should recover the test baseband with useful SNR.');
assert(ideal.metrics.estimatedAMBandwidthHz > 1000, ...
    'Estimated AM bandwidth should be non-trivial for the test message.');
assert(~ideal.metrics.overmodulated, 'Default test settings should not overmodulate.');

mismatchOptions = options;
mismatchOptions.receiverPhaseOffsetDeg = 55;
mismatchOptions.receiverFreqOffsetHz = 35;
mismatch = runAMExperiment(x, fs, mismatchOptions);
assert(mismatch.metrics.reconstructionSnrDb < ideal.metrics.reconstructionSnrDb - 3, ...
    'Coherent receiver mismatch should reduce reconstruction SNR.');

noisyOptions = options;
noisyOptions.channelSnrDb = 5;
noisy = runAMExperiment(x, fs, noisyOptions);
assert(noisy.metrics.channelSnrMeasuredDb > 3 && noisy.metrics.channelSnrMeasuredDb < 7, ...
    'Measured local AWGN SNR should track the requested target.');
assert(noisy.metrics.reconstructionSnrDb < ideal.metrics.reconstructionSnrDb, ...
    'Noisy channel should degrade reconstruction compared with clean channel.');

fprintf('test_30_am_lab_core passed: matched/mismatched/noisy AM paths are coherent.\n');
