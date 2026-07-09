# V2.5 Final Round — audio-driven diagnosis and design changes

This round was designed from the uploaded source/output audio, not from preset tuning alone.

## Observed current case

Source: `zongcisheng.wav`

- MATLAB project profile previously reported source F0 median: 305.8911 Hz.
- An independent offline pitch analysis over the same early speech region gave an approximate source median of 309.4 Hz; estimator differences are expected, so the important evidence is the relative movement between source and outputs.
- Approximate pitch medians from the same independent analysis:
  - source: 309.4 Hz
  - male output: 269.4 Hz
  - female output: 314.9 Hz
  - child output: 318.5 Hz
  - elder output: 287.1 Hz

The previous male result therefore moved pitch only partially and retained many high excursions. The previous female and child results had almost the same pitch center.

Broad spectral-energy diagnosis (normalized within the analysis range) also showed:

- source 80–300 Hz share: about 10.0%
- previous male 80–300 Hz share: about 37.1%
- previous elder 80–300 Hz share: about 28.8%

This supports the reported listening impression that the male result became too heavy/boomy ("fat") rather than convincingly male, and that elder conversion mainly became warmer/lower without enough age cues.

The previous female and child broad spectral distributions were also very close, explaining why child identity was weak.

Additional uploaded examples covered materially different pitch regions (roughly from about 200 Hz to about 392 Hz with the independent estimator) and included stereo cases with low or negative inter-channel correlation. Therefore the final round also removes naive `mean(x,2)` downmix from the main audition/configurable paths and uses the project's anti-cancellation-aware preprocessing.

## Final algorithm changes

1. Robust source profile
   - energy-aware anti-cancellation downmix
   - F0 octave-error correction for clear tracker mistakes
   - local robust smoothing of isolated one-frame pitch jumps

2. Source-adaptive style mapping
   - one fixed semitone preset is no longer used for all sources
   - target F0 region is computed from source register and style anchor
   - large residual distance is shared with envelope/formant-direction processing instead of only broad low-frequency boosting

3. Full-file pitch path for loaded audio
   - full-utterance `shiftPitch` path with phase locking and formant preservation when available
   - larger analysis window and overlap attempt, with compatibility fallbacks
   - avoids the short-frame delay-shifter modulation heard in earlier revisions

4. Cepstral full-file spectral-envelope warp
   - overlapping STFT
   - cepstrally smoothed log spectral envelope
   - bounded frequency-axis envelope warp
   - time-smoothed gain and overlap-add reconstruction
   - replaces the old coarse low-frequency-heavy shaping in loaded-file quality output

5. Style separation
   - male: stronger source-adaptive F0 placement, downward envelope direction, restrained low-band boost
   - female: moderate F0-region mapping plus upward envelope direction and gentle brightness
   - child: source-aware F0 mapping plus clearly stronger upward envelope shift than female
   - elder: stronger age-direction pitch mapping for very-high sources, restrained warmth, breathiness, stable dynamics, and subtle deterministic tremor/micro-delay modulation

6. Batch workflow
   - every source in sibling `Voice_test` can be processed
   - outputs remain under `results/audio/by_source/<source>/...`
   - unique run IDs prevent overwriting earlier results

## Validation boundary

The build includes regression tests and static structural checks. The development environment used to assemble the patch does not contain MATLAB R2025b, so final runtime acceptance must be performed with `tests/run_v25_final_suite.m` on the user's MATLAB installation.

This remains a DSP voice-style conversion system. It is intended to be the strongest practical MATLAB-only version for this course project, but it should not be described as equivalent to a neural zero-shot speaker-conversion model.
