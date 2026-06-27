%TEST_04_MOD_DEMOD Validate AM modulation/demodulation and report figures.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

fs = 16000;
t = (0:1/fs:1-1/fs).';
baseband = 0.35 * sin(2 * pi * 300 * t) + 0.18 * sin(2 * pi * 900 * t);
baseband = baseband(:);

config = makeDefaultConfig();
assert(~config.modDemod.enabled, 'Default modDemod.enabled must be false.');

[defaultY, defaultState] = processAudioFrame(baseband, fs, config);
assert(isstruct(defaultState), 'Default frame processing must return state.');
assert(numel(defaultY) == numel(baseband), 'Default frame output length must match input.');
assert(max(abs(defaultY - baseband)) < 1e-12, 'Default modDemod path should not change the signal.');

modConfig = config.modDemod;
modConfig.enabled = true;
modConfig.type = 'am_modulate';
modConfig.mode = 'legacy_value_should_not_override_type';
modConfig.carrierFreq = 4000;
modConfig.modulationIndex = 0.7;
modConfig.messageScale = 0.8;
modConfig.initialPhase = 0;

[modSig, modOut, modState] = applyModDemod(baseband, fs, modConfig, initProcessState(config));
assert(isstruct(modState), 'AM modulation must return state.');
assert(numel(modSig) == numel(baseband), 'Modulated signal length must match input.');
assert(numel(modOut) == numel(baseband), 'AM modulation primary output length must match input.');
assert(isa(modSig, 'double') && isa(modOut, 'double'), 'AM modulation outputs must be double.');
assert(iscolumn(modSig) && iscolumn(modOut), 'AM modulation outputs must be column vectors.');
assert(all(isfinite(modSig)) && all(isfinite(modOut)), 'AM modulation outputs must be finite.');
assert(max(abs(modSig - modOut)) < 1e-12, 'AM modulation should expose the modulated signal as primary output.');

demodConfig = config.modDemod;
demodConfig.enabled = true;
demodConfig.type = 'am_demodulate';
demodConfig.carrierFreq = modConfig.carrierFreq;
demodConfig.lowpassCutoff = 1500;
demodConfig.filterOrder = 4;
demodConfig.useZeroPhase = true;
demodConfig.normalizeOutput = true;

[~, demodSig, demodState] = applyModDemod(modSig, fs, demodConfig, initProcessState(config));
assert(isstruct(demodState), 'AM demodulation must return state.');
assert(numel(demodSig) == numel(baseband), 'Demodulated signal length must match input.');
assert(isa(demodSig, 'double'), 'Demodulated signal must be double.');
assert(iscolumn(demodSig), 'Demodulated signal must be a column vector.');
assert(all(isfinite(demodSig)), 'Demodulated signal must be finite.');

frameConfig = config;
frameConfig.modDemod = modConfig;
[frameMod, frameState] = processAudioFrame(baseband(1:511), fs, frameConfig);
assert(isstruct(frameState), 'Frame AM modulation must return state.');
assert(isfield(frameState, 'modDemod'), 'Frame AM modulation must keep modDemod state.');
assert(numel(frameMod) == 511, 'Frame AM modulation output length must match input.');
assert(all(isfinite(frameMod)), 'Frame AM modulation output must be finite.');

baseInfo = analyzeSpectrum(baseband, fs, config.display);
modInfo = analyzeSpectrum(modSig, fs, config.display);
demodInfo = analyzeSpectrum(demodSig, fs, config.display);
assert(~isempty(baseInfo.f) && baseInfo.f(1) == 0, 'Baseband spectrum must start at 0 Hz.');
assert(~isempty(modInfo.f) && modInfo.f(end) <= fs / 2 + fs / numel(modSig), 'Modulated spectrum must stay within Nyquist.');
assert(numel(demodInfo.f) == numel(demodInfo.mag), 'Demodulated spectrum f/mag lengths must match.');
assert(all(isfinite(baseInfo.magDb)) && all(isfinite(modInfo.magDb)) && all(isfinite(demodInfo.magDb)), 'Spectra must be finite.');
carrierDb = magAt(modInfo, modConfig.carrierFreq);
lower300Db = magAt(modInfo, modConfig.carrierFreq - 300);
upper300Db = magAt(modInfo, modConfig.carrierFreq + 300);
lower900Db = magAt(modInfo, modConfig.carrierFreq - 900);
upper900Db = magAt(modInfo, modConfig.carrierFreq + 900);
assert(carrierDb > -12, 'AM spectrum should show a visible carrier near 4 kHz.');
assert(min([lower300Db, upper300Db, lower900Db, upper900Db]) > -35, ...
    'AM spectrum should show visible sidebands around the carrier.');
assert(magAt(demodInfo, 300) > magAt(demodInfo, modConfig.carrierFreq) + 25, ...
    'Demodulated spectrum should recover low-frequency content and suppress the carrier.');

figureDir = fullfile(projectRoot, 'results', 'figures');
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

waveformPath = fullfile(figureDir, 'test_04_mod_demod_waveform.png');
spectrumPath = fullfile(figureDir, 'test_04_mod_demod_spectrum.png');

maxPlotSamples = round(0.02 * fs);
plotTime = t(1:maxPlotSamples);

figWave = figure('Visible', 'off', 'Color', 'w', 'Name', 'AM Waveform Comparison');
subplot(3, 1, 1);
plot(plotTime, baseband(1:maxPlotSamples), 'Color', [0.1, 0.35, 0.75]);
grid on;
title('Baseband Signal');
xlabel('Time (s)');
ylabel('Amplitude');

subplot(3, 1, 2);
plot(plotTime, modSig(1:maxPlotSamples), 'Color', [0.75, 0.25, 0.1]);
grid on;
title('AM Modulated Signal');
xlabel('Time (s)');
ylabel('Amplitude');

subplot(3, 1, 3);
plot(plotTime, demodSig(1:maxPlotSamples), 'Color', [0.2, 0.55, 0.25]);
grid on;
title('Coherently Demodulated Signal');
xlabel('Time (s)');
ylabel('Amplitude');
exportgraphics(figWave, waveformPath, 'Resolution', 150);
close(figWave);

figSpec = figure('Visible', 'off', 'Color', 'w', 'Name', 'AM Spectrum Comparison');
subplot(3, 1, 1);
plot(baseInfo.f, baseInfo.magDb, 'Color', [0.1, 0.35, 0.75]);
grid on;
title('Baseband Spectrum');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

subplot(3, 1, 2);
plot(modInfo.f, modInfo.magDb, 'Color', [0.75, 0.25, 0.1]);
grid on;
title('AM Modulated Spectrum');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

subplot(3, 1, 3);
plot(demodInfo.f, demodInfo.magDb, 'Color', [0.2, 0.55, 0.25]);
grid on;
title('Demodulated Spectrum');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
exportgraphics(figSpec, spectrumPath, 'Resolution', 150);
close(figSpec);

assert(exist(waveformPath, 'file') == 2, 'AM waveform figure should be saved.');
assert(exist(spectrumPath, 'file') == 2, 'AM spectrum figure should be saved.');

disp('test_04_mod_demod passed: AM modulation/demodulation and figures work.');

function valueDb = magAt(info, freq)
[~, idx] = min(abs(info.f - freq));
valueDb = info.magDb(idx);
end
