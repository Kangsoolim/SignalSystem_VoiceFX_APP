function config = makeDefaultConfig()
%MAKEDEFAULTCONFIG Create the default project configuration scaffold.
%   This file only defines interface-level options. Concrete algorithms will
%   be implemented later inside core/ and modules/.

config = struct();

config.audio = struct();
config.audio.defaultFs = 44100;
config.audio.frameLength = 1024;
config.audio.numChannels = 1;
config.audio.inputType = 'double_column';
% Keep preprocessing conservative by default. Full-file normalization may
% be enabled explicitly for offline validation/export, but realtime/App
% per-frame normalization should stay disabled unless a later stage adds a
% dedicated loudness strategy.
config.audio.removeDC = false;
config.audio.normalizeInput = false;
config.audio.normalizeTargetPeak = 0.99;

config.noise = struct();
config.noise.enabled = false;
config.noise.type = 'none';
config.noise.mode = 'none';
config.noise.whiteMode = 'fixed';
config.noise.snrDb = 18;
config.noise.noiseLevel = 0.022;
config.noise.whiteFloorLevel = 0.012;
config.noise.whiteAttackTime = 0.30;
config.noise.whiteReleaseTime = 1.00;
config.noise.seed = [];
config.noise.impulseProbability = 0.0015;
config.noise.humAmplitude = 0.04;
config.noise.humHarmonicRatio = 0.35;
config.noise.params = struct();

config.filter = struct();
config.filter.enabled = false;
config.filter.type = 'none';
config.filter.mode = 'none';
config.filter.order = 3;
config.filter.cutoff = [];
config.filter.lowCutoff = 100;
config.filter.highCutoff = 4500;
config.filter.lowpassCutoff = 2700;
config.filter.bandpassLowCutoff = 150;
config.filter.bandpassHighCutoff = 3600;
config.filter.voiceLowCutoff = 95;
config.filter.voiceHighCutoff = 4800;
config.filter.notchFreq = 50;
config.filter.bandwidth = 4;
config.filter.useZeroPhase = false;
config.filter.params = struct();

config.voice = struct();
config.voice.enabled = false;
config.voice.type = 'none';
config.voice.mode = 'none';
config.voice.mix = 1.0;
config.voice.intensity = 0.6;
config.voice.pitchShift = 0;
config.voice.lowGain = 0;
config.voice.highGain = 0;
config.voice.roughness = 0.15;
config.voice.modFreq = 35;
config.voice.params = struct();

config.fx = struct();
config.fx.enabled = false;
config.fx.type = 'none';
config.fx.mode = 'none';
config.fx.mix = 1.0;
config.fx.intensity = 0.6;
config.fx.bitDepth = 8;
config.fx.modFreq = 35;
config.fx.drive = 1.5;
config.fx.params = struct();

config.space = struct();
config.space.enabled = false;
config.space.type = 'none';
config.space.mode = 'none';
config.space.mix = 0.35;
config.space.delayTime = 0.25;
config.space.feedback = 0.35;
config.space.reverbAmount = 0.4;
config.space.params = struct();

config.modDemod = struct();
config.modDemod.enabled = false;
config.modDemod.type = 'none';
config.modDemod.mode = 'none';
config.modDemod.carrierFreq = 4000;
config.modDemod.modulationIndex = 0.7;
config.modDemod.messageScale = 0.8;
config.modDemod.initialPhase = 0;
config.modDemod.lowpassCutoff = 3400;
config.modDemod.filterOrder = 4;
config.modDemod.useZeroPhase = false;
config.modDemod.normalizeOutput = true;
config.modDemod.params = struct();

config.output = struct();
config.output.limitEnabled = true;
config.output.peakLimit = 1.0;
config.output.limitRange = [-1, 1];
% Default remains hard clipping to preserve existing baseline artifacts.
% Set limiterMode to 'soft' only when a smoother safety guard is desired.
config.output.limiterMode = 'hard';

config.display = struct();
config.display.enabled = false;
config.display.mode = 'none';
config.display.saveFigure = false;
config.display.outputDir = fullfile('results', 'figures');
config.display.figureName = 'signal_info.png';
config.display.useDb = true;
config.display.dbFloor = -120;
config.display.maxDurationToPlot = 2;
config.display.params = struct();
end
