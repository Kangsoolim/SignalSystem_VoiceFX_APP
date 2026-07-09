function info = run_v25_noise_denoise_demo(inputArg, scenario)
%RUN_V25_NOISE_DENOISE_DEMO Export preserved noisy/denoised comparison WAVs.
%
%   Input may be a full path or a filename in ../Voice_test.
%   Repeated runs never overwrite earlier audio.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if nargin < 1 || isempty(inputArg)
    inputPath = fullfile(projectRoot, 'samples', ...
        'spoken_monologue_Oscar Winning Tears.wav');
else
    inputPath = resolveVoiceTestInput(inputArg, projectRoot);
end
if nargin < 2 || isempty(scenario)
    scenario = 'babble_crowd';
end
if exist(inputPath, 'file') ~= 2
    error('run_v25_noise_denoise_demo:InputMissing', ...
        'Input audio not found: %s', inputPath);
end

[xRaw, fs] = audioread(inputPath);
config = makeDefaultConfig();
x = preprocessAudio(xRaw, fs, config);

noiseConfig = config.noise;
noiseConfig.enabled = true;
noiseConfig.type = scenario;
noiseConfig.mode = scenario;
noiseConfig.seed = 2026;
noiseConfig.snrDb = 8;
noiseConfig.whiteMode = 'snr';
[noisy, noiseState] = addNoise(x, fs, noiseConfig, initProcessState(config));

filterConfig = makeDefaultConfig();
filterConfig.audio.frameLength = 512;
filterConfig.filter.enabled = true;
filterConfig.filter.type = 'speech_clean';
filterConfig.filter.mode = 'speech_clean';
[denoised, filterState] = processAudioFile(noisy, fs, filterConfig);

category = ['noise_', char(scenario)];
[runDir, runId, sourceName] = createUniqueResultRun( ...
    projectRoot, inputPath, category);

noisyPath = fullfile(runDir, sprintf('%s__01_%s_noisy.wav', ...
    sourceName, scenario));
denoisedPath = fullfile(runDir, sprintf('%s__02_%s_denoised.wav', ...
    sourceName, scenario));

audiowrite(noisyPath, safeAudio(noisy), fs);
audiowrite(denoisedPath, safeAudio(denoised), fs);

info = struct();
info.inputPath = inputPath;
info.sourceName = sourceName;
info.scenario = scenario;
info.runId = runId;
info.runDir = runDir;
info.noisyPath = noisyPath;
info.denoisedPath = denoisedPath;
info.noiseState = noiseState;
info.filterState = filterState;

fprintf('Noise/denoise demo exported without overwriting previous runs:\n');
fprintf('  %s\n  %s\n', noisyPath, denoisedPath);
end

function y = safeAudio(x)
y = double(x(:));
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98*y/peak;
end
end
