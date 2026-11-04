function exportInfo = export_stage3_sample_audition()
%EXPORT_STAGE3_SAMPLE_AUDITION Run Stage 3 noise/filter modes on public samples.
%   Creates per-sample wav outputs plus one concatenated audition file under
%   results/stage3_sample_audition. It does not clear or rebuild other
%   results folders.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

samplesDir = fullfile(projectRoot, 'samples');
outputRoot = fullfile(projectRoot, 'results', 'stage3_sample_audition_v3');
perSampleDir = fullfile(outputRoot, 'per_sample');
ensureDir(outputRoot);
ensureDir(perSampleDir);

sampleFiles = dir(fullfile(samplesDir, '*.wav'));
if isempty(sampleFiles)
    error('exportStage3SampleAudition:NoSamples', 'No wav files found under samples/.');
end

baseConfig = makeAuditionConfig();
noiseModes = {'white', 'hum50', 'impulse'};
filterModes = {'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};
clipOrder = [{'original'}, strcat('noise_', noiseModes), {'filter_input_hum_hiss'}, strcat('filter_', filterModes)];

montageFs = 16000;
montage = zeros(0, 1);
rows = {};
exportInfo = struct();
exportInfo.outputRoot = outputRoot;
exportInfo.perSampleOutputs = {};
exportInfo.auditionFile = fullfile(outputRoot, 'stage3_real_samples_audition_all_v3.wav');
exportInfo.summaryPath = fullfile(outputRoot, 'stage3_real_samples_summary_v3.txt');

for sampleIndex = 1:numel(sampleFiles)
    inputPath = fullfile(sampleFiles(sampleIndex).folder, sampleFiles(sampleIndex).name);
    [xRaw, fs] = audioread(inputPath);
    x = preprocessAudio(xRaw, fs, baseConfig);
    x = limitDuration(x, fs, 6.0);
    x = safeLimiter(x, baseConfig);

    safeName = makeSafeFolderName(sampleFiles(sampleIndex).name);
    sampleOutDir = fullfile(perSampleDir, safeName);
    ensureDir(sampleOutDir);

    outputs = struct();
    outputs.original = x;
    rows(end + 1, :) = {sampleFiles(sampleIndex).name, 'original', '00_original_preprocessed.wav'}; %#ok<AGROW>
    exportInfo.perSampleOutputs{end + 1} = writeAudio(sampleOutDir, '00_original_preprocessed.wav', x, fs, baseConfig); %#ok<AGROW>

    for k = 1:numel(noiseModes)
        mode = noiseModes{k};
        cfg = baseConfig;
        cfg.noise.enabled = true;
        cfg.noise.type = mode;
        cfg.noise.seed = 9100 + 97 * sampleIndex + k;
        cfg.noise.whiteMode = 'fixed';
        cfg.noise.snrDb = 16;
        cfg.noise.whiteFloorLevel = 0.014;
        cfg.noise.humAmplitude = 0.065;
        cfg.noise.humHarmonicRatio = 0.40;
        cfg.noise.impulseProbability = 0.002;
        cfg.noise.noiseLevel = 0.024;

        [y, ~] = processAudioFile(x, fs, cfg);
        fieldName = ['noise_', mode];
        fileName = sprintf('01_noise_%s.wav', mode);
        outputs.(fieldName) = y;
        rows(end + 1, :) = {sampleFiles(sampleIndex).name, fieldName, fileName}; %#ok<AGROW>
        exportInfo.perSampleOutputs{end + 1} = writeAudio(sampleOutDir, fileName, y, fs, baseConfig); %#ok<AGROW>
    end

    rng(11000 + sampleIndex, 'twister');
    filterInput = addFilterTestNoise(x, fs);
    filterInput = safeLimiter(filterInput, baseConfig);
    outputs.filter_input_hum_hiss = filterInput;
    rows(end + 1, :) = {sampleFiles(sampleIndex).name, 'filter_input_hum_hiss', '02_filter_input_hum_hiss.wav'}; %#ok<AGROW>
    exportInfo.perSampleOutputs{end + 1} = writeAudio(sampleOutDir, '02_filter_input_hum_hiss.wav', filterInput, fs, baseConfig); %#ok<AGROW>

    for k = 1:numel(filterModes)
        mode = filterModes{k};
        cfg = makeFilterConfig(baseConfig, mode, fs);
        [y, ~] = processAudioFile(filterInput, fs, cfg);
        fieldName = ['filter_', mode];
        fileName = sprintf('03_filter_%s.wav', mode);
        outputs.(fieldName) = y;
        rows(end + 1, :) = {sampleFiles(sampleIndex).name, fieldName, fileName}; %#ok<AGROW>
        exportInfo.perSampleOutputs{end + 1} = writeAudio(sampleOutDir, fileName, y, fs, baseConfig); %#ok<AGROW>
    end

    montage = appendSampleBlock(montage, outputs, clipOrder, fs, montageFs, sampleIndex);
end

audiowrite(exportInfo.auditionFile, safeLimiter(montage, baseConfig), montageFs);
writeSummary(exportInfo.summaryPath, sampleFiles, clipOrder, rows, outputRoot, exportInfo.auditionFile);

disp('export_stage3_sample_audition finished:');
disp(outputRoot);
disp(exportInfo.auditionFile);
end

function config = makeAuditionConfig()
config = makeDefaultConfig();
config.audio.frameLength = 2048;
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.86;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
end

function cfg = makeFilterConfig(baseConfig, mode, fs)
cfg = baseConfig;
cfg.filter.enabled = true;
cfg.filter.type = mode;
cfg.filter.order = 3;
cfg.filter.cutoff = [];
cfg.filter.lowCutoff = 100;
cfg.filter.highCutoff = min(4500, 0.45 * fs);
cfg.filter.notchFreq = 50;
cfg.filter.bandwidth = 5;
cfg.filter.useZeroPhase = false;

if strcmp(mode, 'highpass')
    cfg.filter.lowCutoff = 140;
elseif strcmp(mode, 'lowpass')
    cfg.filter.highCutoff = min(2700, 0.45 * fs);
elseif strcmp(mode, 'bandpass')
    cfg.filter.lowCutoff = 150;
    cfg.filter.highCutoff = min(3600, 0.45 * fs);
elseif strcmp(mode, 'voice_enhance')
    cfg.filter.lowCutoff = 95;
    cfg.filter.highCutoff = min(4800, 0.45 * fs);
end
end

function y = addFilterTestNoise(x, fs)
n = numel(x);
t = (0:n-1).' / fs;
hissFreq = min(6500, 0.38 * fs);
hum = 0.065 * sin(2 * pi * 50 * t) + 0.022 * sin(2 * pi * 100 * t + pi / 7);
hissTone = 0.030 * sin(2 * pi * hissFreq * t);
hissNoise = 0.010 * randn(size(x));
y = x + hum + hissTone + hissNoise;
end

function montage = appendSampleBlock(montage, outputs, clipOrder, fs, montageFs, sampleIndex)
longGap = zeros(round(0.90 * montageFs), 1);
shortGap = zeros(round(0.35 * montageFs), 1);
cue = makeCue(sampleIndex, montageFs);
montage = [montage; longGap; cue; shortGap]; %#ok<AGROW>

for k = 1:numel(clipOrder)
    name = clipOrder{k};
    clip = outputs.(name);
    clip = limitDuration(clip, fs, 3.5);
    clip = resampleLinear(clip, fs, montageFs);
    clip = fadeEdges(clip, montageFs);
    montage = [montage; clip; shortGap]; %#ok<AGROW>
end
end

function cue = makeCue(sampleIndex, fs)
beep = makeTone(880, 0.11, fs, 0.20);
gap = zeros(round(0.08 * fs), 1);
cue = zeros(0, 1);
for k = 1:sampleIndex
    cue = [cue; beep; gap]; %#ok<AGROW>
end
end

function tone = makeTone(freq, seconds, fs, amp)
t = (0:max(1, round(seconds * fs))-1).' / fs;
tone = amp * sin(2 * pi * freq * t);
tone = fadeEdges(tone, fs);
end

function y = limitDuration(x, fs, maxSeconds)
x = x(:);
maxSamples = min(numel(x), max(1, round(maxSeconds * fs)));
y = x(1:maxSamples);
end

function y = resampleLinear(x, fsIn, fsOut)
x = double(x(:));
if fsIn == fsOut || isempty(x)
    y = x;
    return;
end
duration = (numel(x) - 1) / fsIn;
tIn = linspace(0, duration, numel(x)).';
tOut = (0:max(1, round(duration * fsOut))).' / fsOut;
y = interp1(tIn, x, tOut, 'linear', 'extrap');
y = y(:);
end

function y = fadeEdges(x, fs)
y = double(x(:));
fadeSamples = min(round(0.015 * fs), floor(numel(y) / 2));
if fadeSamples <= 1
    return;
end
fade = linspace(0, 1, fadeSamples).';
y(1:fadeSamples) = y(1:fadeSamples) .* fade;
y(end-fadeSamples+1:end) = y(end-fadeSamples+1:end) .* flipud(fade);
end

function pathName = writeAudio(audioDir, fileName, x, fs, config)
pathName = fullfile(audioDir, fileName);
y = safeLimiter(x, config);
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98 * y / peak;
end
audiowrite(pathName, y, fs);
end

function writeSummary(pathName, sampleFiles, clipOrder, rows, outputRoot, auditionFile)
fid = fopen(pathName, 'w');
if fid < 0
    error('exportStage3SampleAudition:SummaryOpenFailed', 'Could not open summary file.');
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'Stage 3 real-sample audition export\n');
fprintf(fid, 'Audition file: %s\n\n', makeRelativePath(auditionFile, outputRoot));
fprintf(fid, 'Audition order inside each sample block:\n');
for k = 1:numel(clipOrder)
    fprintf(fid, '%02d. %s\n', k, clipOrder{k});
end

fprintf(fid, '\nSample block cue beeps:\n');
for k = 1:numel(sampleFiles)
    fprintf(fid, '- %d beep(s): sample_%02d %s\n', k, k, makeSafeFolderName(sampleFiles(k).name));
end

fprintf(fid, '\nPer-sample files:\n');
for k = 1:size(rows, 1)
    safeName = makeSafeFolderName(rows{k, 1});
    fprintf(fid, '- %s | %s | per_sample/%s/%s\n', safeName, rows{k, 2}, safeName, rows{k, 3});
end
end

function safeName = makeSafeFolderName(fileName)
[~, stem] = fileparts(fileName);
safeName = regexprep(stem, '[''`]', '');
safeName = regexprep(safeName, '[^ -~]', '');
safeName = regexprep(safeName, '[^A-Za-z0-9_]+', '_');
safeName = regexprep(safeName, '_+', '_');
safeName = regexprep(safeName, '^_+|_+$', '');
if isempty(safeName)
    safeName = 'sample';
end
end

function relPath = makeRelativePath(pathName, outputRoot)
prefix = [outputRoot, filesep];
if strncmp(pathName, prefix, numel(prefix))
    relPath = pathName(numel(prefix) + 1:end);
else
    [~, stem, ext] = fileparts(pathName);
    relPath = [stem, ext];
end
relPath = strrep(relPath, filesep, '/');
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end
