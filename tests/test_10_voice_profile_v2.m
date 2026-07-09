%TEST_10_VOICE_PROFILE_V2 Validate richer source voice analysis.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:3.0-1/fs).';
f0 = 180;

% Harmonic speech-like carrier with slow energy modulation.
carrier = 0.28 * sin(2*pi*f0*t) + ...
    0.14 * sin(2*pi*2*f0*t) + ...
    0.07 * sin(2*pi*3*f0*t);

envelope = 0.55 + 0.45 * (0.5 + 0.5*sin(2*pi*3.2*t));
x = carrier .* envelope;

% Insert two pauses to test speech activity / pause extraction.
x(round(0.80*fs):round(1.00*fs)) = 0;
x(round(1.80*fs):round(2.05*fs)) = 0;

profile = analyzeVoiceProfile(x, fs);

assert(strcmp(profile.status, 'ok'), 'Expected voiced profile status=ok.');
assert(abs(profile.f0Median - f0) < 10, 'Median F0 should be near 180 Hz.');
assert(profile.speechActivityRatio > 0.50 && profile.speechActivityRatio < 1.0, ...
    'Speech activity ratio should reflect inserted pauses.');
assert(profile.pauseCount >= 1, 'At least one internal pause should be detected.');
assert(isfinite(profile.spectralCentroidMedian), 'Spectral centroid must be finite.');
assert(isfinite(profile.spectralFlatnessMean), 'Spectral flatness must be finite.');
assert(isfinite(profile.energyModulationRateHz), 'Rhythm proxy must be finite.');
assert(profile.dynamicRangeDb >= 0, 'Dynamic range must be nonnegative.');
assert(profile.pitchRangeSemitones >= 0, 'Pitch range in semitones must be nonnegative.');

silentProfile = analyzeVoiceProfile(zeros(fs,1), fs);
assert(strcmp(silentProfile.status, 'unvoiced'), 'Silence must be unvoiced.');
assert(silentProfile.voicedRatio == 0, 'Silence voiced ratio must be zero.');

disp('test_10_voice_profile_v2 passed: richer voice profile works.');
disp(profile);
