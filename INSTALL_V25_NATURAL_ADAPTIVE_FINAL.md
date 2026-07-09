# VoiceFX V2.5 Natural Adaptive Final Patch

This is the final naturalness-priority voice-core optimization.

## What changed

The voice planner no longer forces every source toward one fixed F0 target.
It now:

1. analyzes source F0 center and range;
2. uses voiced ratio and pitch confidence to estimate safe processing strength;
3. preserves wide expressive pitch contours by reducing the global shift budget;
4. uses speech rhythm proxies only to tune dynamics timing, without time-stretching speech;
5. uses broad style F0 regions as soft direction priors;
6. limits pitch movement with a smooth saturation rule;
7. applies only mild source-dependent envelope, excitation, and dynamics shaping;
8. removes the aggressive HQ cepstral envelope warp and elder micro-delay stage from the active file-processing chain.

The four public style IDs remain unchanged:
- male_deep_gentle
- female_gentle_sweet
- child_bright_soft
- elder_warm_steady

The names remain compatible with the existing App/scripts, but the internal target is now natural category conversion rather than extreme style forcing.

## Preserved project behavior

- One unified pipeline.
- Independent noise/filter/voice/fx/space/mod-demod/display switches.
- Voice_test automatic filename lookup.
- Per-source results directories.
- Unique run IDs; previous outputs are not overwritten.
- Batch conversion through run_v25_batch_four_style().

## Install

Copy all contents of this patch root into:

D:\Projects\SignalSystem_VoiceFX_APP

Choose:
- merge folders
- replace files with the same name

Do not delete the project directory and do not run git init.

## Validate

In MATLAB:

cd('D:\Projects\SignalSystem_VoiceFX_APP');
addpath(genpath(pwd));
clear functions;
rehash;

run('tests/run_v25_final_suite.m');

Expected final line:

ALL V2.5 NATURAL FINAL TESTS PASSED.

## Diagnose one source

report = run_v25_source_diagnostics('zongcisheng.wav');

The report shows:
- source F0 median
- pitch range
- target F0 band
- planned output F0
- pitch shift
- formant scale
- envelope strength
- prosody retention

## Generate four outputs for one source

summary = run_v25_first_round_audition('zongcisheng.wav');

## Batch all supported files in sibling Voice_test

batch = run_v25_batch_four_style();

Outputs remain under:

results/audio/by_source/<source>/four_style/<run_id>/

## Important design boundary

This is a source-adaptive MATLAB DSP voice-style system. The algorithm is optimized for naturalness and stability, not for neural zero-shot speaker cloning. Broad style regions guide the direction, while source pitch, pitch range, voicing confidence, spectral balance, dynamic range, and rhythm proxies determine how much processing is applied.
