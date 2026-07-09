# Realtime Voice Processing

## Dashboard launch

```matlab
fig = launchVoiceFXDashboard();
```

Open **LIVE STUDIO** to select devices, frame size, voice style, speech cleaning,
device FX and space FX. Voice/FX/space controls remain live-updatable while a session
runs; sample rate, frame size and device routing are locked until the session stops.

## List devices

```matlab
devices = listAudioDevices();
```

The returned struct contains `input`, `output`, and, when available, `duplex` device lists.

## Minimal CLI run

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

## Split input/output devices

```matlab
options = struct();
options.sampleRate = 48000;
options.frameLength = 512;
options.ioMode = 'split';
options.intensity = 0.62;
options.enableSpeechClean = true;
options.fxMode = 'telephone';
options.fxMix = 0.7;
stats = runRealtimeVoiceChanger(30, 'female', options);
```

## Full-duplex device path

```matlab
options = struct();
options.sampleRate = 48000;
options.frameLength = 512;
options.ioMode = 'duplex';
stats = runRealtimeVoiceChanger(30, 'anonymous', options);
```

`duplex` mode requires Audio Toolbox `audioPlayerRecorder`. `split` mode keeps the
original `audioDeviceReader` + `audioDeviceWriter` route and supports different input and
output device names.

## Interactive integration callbacks

`runRealtimeVoiceChanger` also accepts:

- `monitorFcn` — receives rolling telemetry snapshots.
- `controlFcn` — returns a full config or option-update struct during the session.
- `stopFcn` — returns logical true when the session should stop.
- `processUIEvents` — lets a programmatic MATLAB UI process button callbacks at monitor cadence.

The Dashboard uses these callbacks; CLI users can ignore them.

## Tuning rules

- Start at 512 samples and confirm overrun/underrun remain zero.
- Try 256 samples only after the system is stable.
- Increase frame size or reduce the processing chain when xruns occur.
- `meanProcessMs` and `p95ProcessMs` are algorithm processing times, not physical
  microphone-to-headphone round-trip latency.
- Keep realtime audio processing in `processAudioFrame`; do not duplicate DSP in UI callbacks.
