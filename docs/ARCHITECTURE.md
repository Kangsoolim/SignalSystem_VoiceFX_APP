# VoiceFX App Project Architecture

## Project Goal

This project builds a MATLAB R2024b App Designer system for realtime voice transformation, music/audio effects, AM modulation-demodulation demos, and signal visualization. The current codebase focuses on reusable MATLAB function modules first; App Designer callbacks should later call these modules instead of embedding DSP logic in UI code.

## Directory Structure

```text
VoiceFX_App_Project/
├─ core/        Shared processing chain, config, state, preprocessing, limiter
├─ modules/     Independent DSP modules: noise, filter, voice, FX, space, AM, plots
├─ realtime/    Future realtime device integration notes and wrappers
├─ app/         Future App Designer entry files and UI notes
├─ tests/       MATLAB script tests for each implementation stage
├─ docs/        Architecture and report-supporting documentation
├─ samples/     Optional small audio samples
└─ results/     Generated audio and figure outputs
```

## Unified Processing Chain

File mode and future realtime mode should share the same frame-level chain:

```text
preprocessAudio
→ addNoise
→ applyDenoiseFilter
→ applyVoiceStyle
→ applyVocalFX
→ applySpaceFX
→ applyModDemod
→ safeLimiter
```

`processAudioFile` splits a full signal into frames and calls `processAudioFrame`. Future realtime callbacks should also call `processAudioFrame`, so module behavior stays consistent between offline demos and live processing.

## Config Layers

`makeDefaultConfig` returns one top-level struct with these main layers:

- `config.audio`: sample-rate defaults, frame length, mono/double conventions, DC removal, input normalization.
- `config.noise`: generated noise modes such as white, hum50, and impulse.
- `config.filter`: traditional filters including highpass, lowpass, bandpass, notch50, and voice_enhance.
- `config.voice`: lightweight voice style modes including male, female, child, elder, anonymous, and robot_voice.
- `config.fx`: future vocal/music effects.
- `config.space`: future delay/reverb and spatial effects.
- `config.modDemod`: AM modulation and coherent demodulation parameters.
- `config.output`: limiter behavior and safe output range.
- `config.display`: spectrum/figure display and save options.

Defaults should keep advanced modules disabled. In particular, `config.modDemod.enabled = false` so the normal audio chain is not changed unless AM mode is explicitly requested.

## State Layers

`initProcessState` creates the shared runtime state. Current and expected layers include:

- `state.filter`: IIR filter memory for frame-continuous denoise filters.
- `state.modDemod`: carrier sample index and lowpass filter memory for AM demodulation.
- `state.voice`, `state.fx`, `state.space`: future stateful voice/effect buffers.
- `state.realtime`: frame counters for shared file/realtime operation.
- `state.debug`: lightweight diagnostics such as last sample rate and frame length.

State should be passed through every module and returned by `processAudioFrame`.

## File Mode and Realtime Mode

File mode is already implemented through `processAudioFile`: it preprocesses the input, splits by `config.audio.frameLength`, and processes each frame through `processAudioFrame`.

Realtime mode should later use the same contract:

```matlab
[yFrame, state] = processAudioFrame(xFrame, fs, config, state);
```

Realtime-safe modules should default to causal `filter`-based processing. Zero-phase `filtfilt` is only appropriate for file-mode demonstrations when explicitly enabled.

## Module Composition

Voice style, vocal effects, space effects, and AM demos are not mutually exclusive at the architecture level. They are chained in a fixed order so later combinations can be built by enabling multiple config layers, for example:

- voice style + telephone effect
- anonymous/interview style + radio or intercom effect
- child/young style + reverb
- robot style + bitcrusher

AM modulation-demodulation is mainly for course-report signal analysis and spectrum-shift demonstration. It is available in the shared chain but should normally stay disabled during voice/effect demos.

## Completed Modules

- Project scaffold and shared frame chain.
- `preprocessAudio`: double column vector, mono conversion, NaN/Inf cleanup, DC removal, normalization.
- `safeLimiter`: hard limiter with configurable range.
- `addNoise`: none, white, hum50, impulse.
- `analyzeSpectrum`: single-sided magnitude and dB spectrum data.
- `applyDenoiseFilter`: none, highpass, lowpass, bandpass, notch50, voice_enhance.
- `plotSignalInfo`: basic waveform/spectrum report figure support.
- `applyModDemod`: AM modulation and coherent demodulation.
- `applyVocalFX`: telephone, walkie_talkie, radio, lofi, bitcrusher, robot.
- `applySpaceFX`: delay, reverb, bathroom, cave, stage.
- `applyVoiceStyle`: lightweight traditional voice-style presets: male, female, child, elder, anonymous, robot_voice.
- `scripts/run_file_demo_pipeline`: offline synthetic demo that exports report-ready audio and figures.

## Placeholder Modules

- `realtime/`: future microphone and audio device integration.
- `app/`: future App Designer UI wiring.

## Suggested Next Stage

The next high-value stage is App Designer integration for file-mode workflows: load or generate audio, choose module presets, run the shared pipeline, preview waveform/spectrum figures, and export results. Realtime microphone integration should come after the file-mode UI is stable.
