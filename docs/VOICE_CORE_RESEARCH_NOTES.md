# Voice Core Research Notes and Engineering Boundary

## Purpose

This document records the research ideas that guided the current MATLAB DSP baseline. The implementation is intentionally lightweight and causal. It does **not** claim to reproduce neural state-of-the-art voice conversion.

## Research directions reviewed

- **StreamVC (ICASSP 2024, arXiv:2401.03078)**: causal streaming voice conversion, soft speech units, explicit F0 conditioning, content/prosody preservation, target-timbre matching.
- **Seed-VC (arXiv:2411.09943)**: zero-shot voice conversion using a diffusion transformer and full-context reference timbre modeling; highlights timbre leakage and training/inference mismatch problems.
- **RT-VC (2025, arXiv:2506.10289)**: real-time zero-shot VC using articulatory coding and a DDSP vocoder; separates content/articulation, pitch/loudness/periodicity, and speaker information.
- **MeanVC 2 (Interspeech 2026, arXiv:2606.09050)**: robust low-latency streaming zero-shot VC with bounded future context and 40 ms chunks; emphasizes chunk stability and robust timbre encoding.
- **DeepFilterNet (arXiv:2110.05588; real-time demo arXiv:2305.08227)**: perceptually motivated full-band enhancement using an ERB-envelope stage plus multi-frame deep filtering; important principle is temporally informed, perceptually structured enhancement rather than independent-frame hard gating.

## Principles translated into the MATLAB baseline

1. **Causal state, never frame reset**  
   Delay buffers, pitch phase, filter memory, gain memory and calibration state are carried in `state`.

2. **Separate pitch placement and timbre shaping**  
   `adaptVoiceStyleConfig` maps source F0 statistics to a bounded semitone offset while `applyVoiceStyle` performs independent spectral/timbre shaping.

3. **Preserve prosody instead of flattening F0**  
   The DSP engine applies a median-region offset and leaves the short-term source contour intact.

4. **Speech-aware calibration**  
   A short calibration buffer builds a stable source voice profile before the wet effect fades in.

5. **Temporal smoothing**  
   Pitch target, speech gate, de-esser gain, RMS compensation and denoise gains change smoothly across frames.

6. **Perceptually coarse multiband enhancement**  
   `speech_clean` uses causal rumble removal, narrow hum notches and four broad speech bands with smooth Wiener-like gains. This is a lightweight DSP approximation, not DeepFilterNet.

7. **Bounded transformation**  
   Pitch offsets and spectral gains are deliberately limited. Aggressive shifts are a major source of metallic artifacts in lightweight time-domain pitch shifters.

## Honest boundary of the current implementation

The current code supports source-aware **voice-style transformation** (male/female/child/elder/anonymous/robot) and low-latency streaming experiments. It does not clone a specific unseen target speaker.

A future professional product aiming at “one target timbre for many users”, arbitrary target references, accent-aware control and high naturalness should add a neural VC engine behind the same App-facing interface. The likely long-term architecture is:

```text
Audio I/O
  -> speech enhancement / AEC
  -> causal content or articulatory representation
  -> source prosody conditioning (F0, loudness, periodicity)
  -> target speaker/timbre representation
  -> streaming conversion model
  -> neural or DDSP vocoder
  -> limiter / device output
```

The existing DSP engine should remain as a fast fallback, test baseline and low-resource mode.
