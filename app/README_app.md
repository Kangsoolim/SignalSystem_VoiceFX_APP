# VoiceFX Dashboard

The project now includes a programmatic MATLAB Dashboard in `app/VoiceFXDashboard.m`.
It intentionally uses `.m` UI code instead of an `.mlapp` binary so the interface is
reviewable in Git and keeps callbacks thin.

## Launch

From the project root in MATLAB R2025b:

```matlab
fig = launchVoiceFXDashboard();
```

The launcher adds the project folders to the MATLAB path and opens three workspaces:

- **Live Studio** — microphone VoiceFX, device routing, live voice/FX/space controls,
  rolling waveform and spectrum, processing-time/RTF/xrun telemetry.
- **AM Lab** — DSB-LC modulation, AWGN channel, coherent receiver phase/frequency
  mismatch, lowpass recovery, waveform/spectrum comparison and recovery metrics.
- **File Studio** — project sample or local file import, realtime-compatible DSP or
  HQ full-utterance engine, playback, before/after plots and WAV export.

## Architecture rule

The Dashboard does not contain alternative audio algorithms. Its callbacks build config,
call `processAudioFrame`, `processAudioFile`, `processAudioFileHighQuality`,
`runAMExperiment`, or `runRealtimeVoiceChanger`, then visualize results. Core DSP remains
inside `core/` and `modules/`.

## Realtime note

The `BUFFER BUDGET*` tile is an internal scheduling indicator derived from frame duration
and processing time. It is not presented as measured acoustic round-trip latency.
Actual round-trip latency depends on driver, hardware and device buffering and needs a
separate loopback measurement.
