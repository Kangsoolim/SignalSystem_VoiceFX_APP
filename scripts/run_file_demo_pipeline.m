function demoInfo = run_file_demo_pipeline()
%RUN_FILE_DEMO_PIPELINE Generate report-ready offline demo artifacts.
%   This demo uses a synthetic speech-like signal. It does not play audio,
%   does not require App Designer, and does not depend on external files.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:2-1/fs).';
original = makeSpeechLikeSignal(t);

config = makeDefaultConfig();
audioDir = fullfile(projectRoot, 'results', 'audio');
figureDir = fullfile(projectRoot, 'results', 'figures');
ensureDir(audioDir);
ensureDir(figureDir);

noiseConfig = config;
noiseConfig.noise.enabled = true;
noiseConfig.noise.type = 'hum50';
noiseConfig.noise.humAmplitude = 0.045;
[noisy, ~] = processAudioFile(original, fs, noiseConfig);

filterConfig = config;
filterConfig.filter.enabled = true;
filterConfig.filter.type = 'voice_enhance';
filterConfig.filter.lowCutoff = 90;
filterConfig.filter.highCutoff = 3600;
[filtered, ~] = processAudioFile(noisy, fs, filterConfig);

voiceConfig = config;
voiceConfig.voice.enabled = true;
voiceConfig.voice.type = 'anonymous';
voiceConfig.voice.intensity = 0.7;
[voiceStyled, ~] = processAudioFile(filtered, fs, voiceConfig);

chainConfig = config;
chainConfig.voice.enabled = true;
chainConfig.voice.type = 'child';
chainConfig.voice.intensity = 0.55;
chainConfig.fx.enabled = true;
chainConfig.fx.type = 'lofi';
chainConfig.fx.mix = 0.8;
chainConfig.fx.intensity = 0.55;
chainConfig.space.enabled = true;
chainConfig.space.type = 'stage';
chainConfig.space.mix = 0.30;
chainConfig.space.reverbAmount = 0.45;
[voiceFxChain, ~] = processAudioFile(filtered, fs, chainConfig);

modConfig = config.modDemod;
modConfig.enabled = true;
modConfig.type = 'am_modulate';
modConfig.carrierFreq = 4000;
modConfig.modulationIndex = 0.7;
modConfig.messageScale = 0.8;
[modulated, ~, modState] = applyModDemod(filtered, fs, modConfig, initProcessState(config));

demodConfig = config.modDemod;
demodConfig.enabled = true;
demodConfig.type = 'am_demodulate';
demodConfig.carrierFreq = modConfig.carrierFreq;
demodConfig.lowpassCutoff = 1800;
demodConfig.useZeroPhase = true;
[~, demodulated, demodState] = applyModDemod(modulated, fs, demodConfig, initProcessState(config)); %#ok<ASGLU>

demoInfo = struct();
demoInfo.fs = fs;
demoInfo.audioDir = audioDir;
demoInfo.figureDir = figureDir;
demoInfo.audioFiles = struct();
demoInfo.figureFiles = struct();
demoInfo.state = struct('mod', modState, 'demod', demodState);

demoInfo.audioFiles.original = writeDemoAudio(audioDir, 'demo_original.wav', original, fs);
demoInfo.audioFiles.noisy = writeDemoAudio(audioDir, 'demo_noisy.wav', noisy, fs);
demoInfo.audioFiles.filtered = writeDemoAudio(audioDir, 'demo_filtered.wav', filtered, fs);
demoInfo.audioFiles.voiceStyle = writeDemoAudio(audioDir, 'demo_voice_style.wav', voiceStyled, fs);
demoInfo.audioFiles.voiceFxChain = writeDemoAudio(audioDir, 'demo_voice_fx_chain.wav', voiceFxChain, fs);
demoInfo.audioFiles.modulated = writeDemoAudio(audioDir, 'demo_modulated.wav', modulated, fs);
demoInfo.audioFiles.demodulated = writeDemoAudio(audioDir, 'demo_demodulated.wav', demodulated, fs);

overviewPath = fullfile(figureDir, 'test_07_demo_pipeline_overview.png');
modPath = fullfile(figureDir, 'test_07_demo_mod_demod.png');
saveOverviewFigure(overviewPath, original, noisy, filtered, voiceStyled, voiceFxChain, fs, config.display);
saveModDemodFigure(modPath, filtered, modulated, demodulated, fs, config.display);
demoInfo.figureFiles.overview = overviewPath;
demoInfo.figureFiles.modDemod = modPath;

disp('run_file_demo_pipeline finished: demo audio and figures generated.');
end

function x = makeSpeechLikeSignal(t)
f0 = 155 + 18 * sin(2 * pi * 1.1 * t);
phase = cumsum(2 * pi * f0 / 16000);
env = 0.55 + 0.35 * sin(2 * pi * 2.2 * t).^2;
vowelA = sin(phase) + 0.45 * sin(2 * phase) + 0.22 * sin(3 * phase);
formants = 0.12 * sin(2 * pi * 700 * t) + 0.08 * sin(2 * pi * 1250 * t) + 0.05 * sin(2 * pi * 2400 * t);
x = env .* (0.35 * vowelA + formants);
x = x(:);
x = x / max(max(abs(x)), eps) * 0.75;
end

function ensureDir(pathName)
if ~exist(pathName, 'dir')
    mkdir(pathName);
end
end

function pathName = writeDemoAudio(audioDir, fileName, x, fs)
pathName = fullfile(audioDir, fileName);
x = double(x);
x = x(:);
x(~isfinite(x)) = 0;
peak = max(abs(x));
if peak > 0.98
    x = 0.98 * x / peak;
end
audiowrite(pathName, x, fs);
end

function saveOverviewFigure(pathName, original, noisy, filtered, voiceStyled, voiceFxChain, fs, displayConfig)
signals = {original, noisy, filtered, voiceStyled, voiceFxChain};
names = {'Original', 'Noisy', 'Filtered', 'Voice Style', 'Voice + FX + Space'};
maxSamples = min(numel(original), round(0.08 * fs));
t = (0:maxSamples-1).' / fs;

fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Demo Pipeline Overview');
for k = 1:numel(signals)
    subplot(numel(signals), 2, 2 * k - 1);
    plot(t, signals{k}(1:maxSamples));
    grid on;
    title([names{k}, ' Waveform']);
    xlabel('Time (s)');
    ylabel('Amp');

    subplot(numel(signals), 2, 2 * k);
    info = analyzeSpectrum(signals{k}, fs, displayConfig);
    plot(info.f, info.magDb);
    grid on;
    title([names{k}, ' Spectrum']);
    xlabel('Frequency (Hz)');
    ylabel('dB');
end
exportgraphics(fig, pathName, 'Resolution', 150);
close(fig);
end

function saveModDemodFigure(pathName, baseband, modulated, demodulated, fs, displayConfig)
signals = {baseband, modulated, demodulated};
names = {'Filtered Baseband', 'AM Modulated', 'AM Demodulated'};
maxSamples = min(numel(baseband), round(0.02 * fs));
t = (0:maxSamples-1).' / fs;

fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'Demo AM Mod/Demod');
for k = 1:numel(signals)
    subplot(3, 2, 2 * k - 1);
    plot(t, signals{k}(1:maxSamples));
    grid on;
    title([names{k}, ' Waveform']);
    xlabel('Time (s)');
    ylabel('Amp');

    subplot(3, 2, 2 * k);
    info = analyzeSpectrum(signals{k}, fs, displayConfig);
    plot(info.f, info.magDb);
    grid on;
    title([names{k}, ' Spectrum']);
    xlabel('Frequency (Hz)');
    ylabel('dB');
end
exportgraphics(fig, pathName, 'Resolution', 150);
close(fig);
end
