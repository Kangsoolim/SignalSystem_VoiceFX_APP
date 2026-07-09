function targetProfile = buildVoiceTargetProfile(referenceAudio, fs, options)
%BUILDVOICETARGETPROFILE Analyze a reusable target/reference voice sample.
%   targetProfile = buildVoiceTargetProfile(referenceAudio, fs)
%
%   The returned profile can be reused for many source users:
%
%       config.voice.params.targetProfile = targetProfile;
%
%   This provides reference-conditioned DSP adaptation (target F0 region and
%   spectral brightness guidance). It is not neural zero-shot speaker cloning.

if nargin < 3 || isempty(options)
    options = struct();
end

referenceAudio = double(referenceAudio);
if ~isvector(referenceAudio)
    referenceAudio = mean(referenceAudio, 2);
end
referenceAudio = referenceAudio(:);
referenceAudio(~isfinite(referenceAudio)) = 0;

if isempty(referenceAudio)
    error('buildVoiceTargetProfile:EmptyReference', ...
        'Reference audio must not be empty.');
end

minimumSeconds = getField(options, 'minimumSeconds', 1.0);
if numel(referenceAudio)/fs < minimumSeconds
    warning('buildVoiceTargetProfile:ShortReference', ...
        'Reference audio is shorter than %.2f s; profile may be unstable.', ...
        minimumSeconds);
end

targetProfile = analyzeVoiceProfile(referenceAudio, fs, options);
if ~strcmp(targetProfile.status, 'ok')
    error('buildVoiceTargetProfile:UnusableReference', ...
        'Reference audio did not yield a stable voiced profile.');
end

targetProfile.profileRole = 'target_reference';
targetProfile.referenceDuration = numel(referenceAudio)/fs;
end

function value = getField(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
