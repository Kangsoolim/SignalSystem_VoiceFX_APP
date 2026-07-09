function output = build_target_voice_profile(referencePath, outputPath)
%BUILD_TARGET_VOICE_PROFILE Build and save a reusable target voice profile.
%
% Example:
%   output = build_target_voice_profile('my_target.wav');
%
% Then in conversion code:
%   loaded = load(output.outputPath);
%   config.voice.params.targetProfile = loaded.targetProfile;

if nargin < 1 || isempty(referencePath)
    error('build_target_voice_profile:ReferenceRequired', ...
        'Provide a WAV reference path.');
end
if exist(referencePath, 'file') ~= 2
    error('build_target_voice_profile:FileNotFound', ...
        'Reference file not found: %s', referencePath);
end

[x, fs] = audioread(referencePath);
targetProfile = buildVoiceTargetProfile(x, fs);

if nargin < 2 || isempty(outputPath)
    [folder, name, ~] = fileparts(referencePath);
    if isempty(folder)
        folder = pwd;
    end
    outputPath = fullfile(folder, [name, '_voice_profile.mat']);
end

save(outputPath, 'targetProfile');
output = struct('outputPath', outputPath, ...
    'referencePath', referencePath, ...
    'sampleRate', fs, ...
    'targetProfile', targetProfile);

fprintf('Target voice profile saved: %s\n', outputPath);
fprintf('  Median F0            : %.2f Hz\n', targetProfile.f0Median);
fprintf('  Spectral centroid    : %.2f Hz\n', ...
    targetProfile.spectralCentroidMedian);
end
