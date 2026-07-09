# V2.5 Final Round installation and acceptance

## 1. Install

Copy the **contents** of the final patch folder into the repository root:

`D:\Projects\SignalSystem_VoiceFX_APP`

Merge folders and replace same-name files. Do not delete the repository's existing folders and do not remove `.git`.

## 2. Clear MATLAB function cache

```matlab
cd('D:\Projects\SignalSystem_VoiceFX_APP');
addpath(genpath(pwd));
clear functions;
rehash;
```

## 3. Run final regression suite

```matlab
run('tests/run_v25_final_suite.m');
```

Expected final line:

`ALL V2.5 FINAL TESTS PASSED.`

## 4. Inspect one source mapping

For a file in sibling `D:\Projects\Voice_test`:

```matlab
report = run_v25_source_diagnostics('zongcisheng.wav');
```

## 5. Generate four outputs for one source

```matlab
summary = run_v25_first_round_audition('zongcisheng.wav');
summary.runDir
```

## 6. Batch-process all supported audio in Voice_test

```matlab
batch = run_v25_batch_four_style();
```

Supported input extensions: WAV, M4A, MP3, FLAC, subject to `audioread` support in the local MATLAB installation.

## 7. One unified switch-controlled pipeline

```matlab
config = makeDefaultConfig();

config.noise.enabled = false;
config.filter.enabled = false;

config.voice.enabled = true;
config.voice.type = 'male_deep_gentle';
config.voice.mode = 'male_deep_gentle';

config.fx.enabled = false;
config.space.enabled = false;
config.modDemod.enabled = false;
config.display.enabled = true;

result = run_v25_configurable_pipeline('zongcisheng.wav', config);
```

Every course module remains independently switchable in the same pipeline.
