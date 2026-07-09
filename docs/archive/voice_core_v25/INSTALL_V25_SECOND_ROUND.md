# VoiceFX V2.5 Second-Round Patch

This patch is based on the first-round V2.5 snapshot.

## Main changes

1. Wide-source adaptation
   - Smooth bounded pitch mapping instead of hard -7 semitone clamping.
   - Source pitch bands: very_low / low / mid / high / very_high.
   - Residual source-target distance is transferred to stronger style-direction
     envelope/formant shaping.
   - Child mapping allows a small downward correction for already very-high
     source voices.
   - Elder preset receives stronger age-direction envelope, tilt, breathiness,
     mild roughness and steadier dynamics.

2. File audition quality
   - `run_v25_first_round_audition` keeps its old function name for compatibility.
   - It now uses `processAudioFileHighQuality` for loaded audio files to avoid
     short-frame dual-delay modulation artifacts in large source-target shifts.
   - All course module switches remain in the single config-controlled pipeline.

3. Result preservation
   - No generated audio is overwritten.
   - A bare filename is resolved from the sibling `Voice_test` folder.
   - Outputs are organized under:
     `results/audio/by_source/<source>/<category>/<run_id>/`
   - Output filenames include the original source basename.

4. New configurable runner
   - `scripts/run_v25_configurable_pipeline.m`
   - One pipeline; individual module switches remain available:
     noise / filter / voice / fx / space / modDemod / display.

## Install

Copy the patch root contents into the existing repository root and choose
"Replace files in the destination" for same-name files. Do not delete the
existing repository folders and do not remove `.git`.

## MATLAB validation

```matlab
% 在 MATLAB 中打开本仓库根目录后运行：
addpath(genpath(pwd));
clear functions;
rehash;
run('tests/run_v25_first_round_suite.m');
```

## Four-style audition from Voice_test

For:
`Voice_test\zongcisheng.wav`

run:

```matlab
summary = run_v25_first_round_audition('zongcisheng.wav');
```

The run is preserved under:
`results/audio/by_source/zongcisheng/four_style/<run_id>/`

## Switch-controlled single pipeline example

```matlab
config = makeDefaultConfig();

config.noise.enabled = true;
config.noise.type = 'babble_crowd';
config.noise.mode = 'babble_crowd';
config.noise.snrDb = 8;

config.filter.enabled = true;
config.filter.type = 'speech_clean';
config.filter.mode = 'speech_clean';

config.voice.enabled = true;
config.voice.type = 'male_deep_gentle';
config.voice.mode = 'male_deep_gentle';

config.fx.enabled = false;
config.space.enabled = false;
config.modDemod.enabled = false;
config.display.enabled = false;

result = run_v25_configurable_pipeline('zongcisheng.wav', config);
```
