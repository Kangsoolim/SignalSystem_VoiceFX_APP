# AM / Dashboard / Realtime Research Map

This note records which external ideas were evaluated and which ones were actually adapted
into this MATLAB project. It deliberately separates **ideas adopted now** from **neural VC
backends that remain future work**, so the repository does not pretend to contain models it
does not ship.

## 1. Product and interface patterns reviewed

### Voicemod / Voice.ai / Altered

Common useful product pattern: realtime conversion, voice/effect selection, routing,
recording or file workflows, and immediate status feedback are presented as one coherent
workspace instead of unrelated demo scripts.

**Adapted here:** one control center with Live Studio, AM Lab, and File Studio. The three
tabs share the same project processing functions instead of duplicating algorithms in UI
callbacks.

### w-okada VCClient

Useful engineering/product ideas reviewed: realtime model switching, chunk/buffer controls,
buffer visualization, and the possibility of separating UI from heavier inference compute.

**Adapted here:** visible frame-size choice, rolling process-time and RTF telemetry,
overrun/underrun accounting, low-frequency waveform/spectrum refresh, and a callback-based
runner that cleanly separates audio processing from UI control.

**Not copied:** remote neural inference server architecture. The current repository is a
MATLAB DSP course project and should not acquire a hidden Python/GPU service dependency.

### Applio realtime releases

Useful ideas reviewed: ASIO-oriented low-latency path, realtime performance work,
realtime worker separation, warm-up behavior, pitch caching, and sliding-window processing.

**Adapted where compatible:** explicit I/O strategy selection, preserved calibration/fade-in
behavior from the existing adaptive voice chain, xrun telemetry, rolling monitoring windows,
and state continuity. Multiprocessing was not forced into MATLAB because the current causal
DSP state is intentionally advanced through one ordered frame chain.

## 2. Open-source and research VC systems reviewed

### RVC

Retrieval-based content features, F0 extraction and target-feature retrieval can materially
improve target-speaker similarity. This is a different problem class from the repository's
source-aware DSP voice styling.

**Decision:** do not silently relabel the current DSP engine as RVC or cloning. Keep a future
backend boundary, but preserve the lightweight DSP engine as the low-resource baseline.

### Seed-VC

Zero-shot diffusion-transformer VC and realtime support were reviewed. The original public
repository was archived in November 2025, and its documented realtime delay is far above the
small-frame DSP loop used here.

**Decision:** useful future quality/reference direction, but not a dependency for this
course-oriented MATLAB realtime chain.

### StreamVC / MeanVC 2 / RT-VC / LLVC

The strongest reusable architectural ideas are causal or bounded-context processing,
explicit pitch/prosody conditioning, compact streaming synthesis, and honest separation of
algorithm latency from device I/O latency.

**Adapted here now:** causal frame state remains the core invariant; UI refresh is decoupled
from the audio frame rate; rolling telemetry reports process time/RTF/xruns; the Dashboard
never labels an internal frame budget as measured acoustic round-trip latency.

**Future backend direction:** a neural backend should implement a stable frame/chunk adapter
behind the existing App-facing control surface rather than replacing the Dashboard or
rewriting the file/realtime orchestration layer.

### DDSP-SVC / so-vits-svc

These projects are valuable references for singing-voice conversion and efficient synthesis,
but their goals, models and runtime stacks are not drop-in replacements for the current
speech-oriented MATLAB DSP project.

**Decision:** retain as research references; do not add misleading menu options for models
that are not packaged and executable.

## 3. AM Lab design rationale

The original AM module already supported modulation and coherent demodulation. The missing
piece was a complete experiment surface. The upgraded AM Lab adds:

- DSB-LC transmitter control (carrier frequency, modulation index, message scale);
- deterministic AWGN channel SNR;
- independent receiver oscillator phase and frequency mismatch;
- causal lowpass recovery through the same `applyModDemod` module;
- bounded small-delay alignment for fair reconstruction metrics;
- correlation, reconstruction SNR, NMSE, baseband/AM bandwidth estimate, and envelope margin;
- waveform, envelope, spectrum-shift, and recovered-signal visualizations.

The AM path stays **off by default** in realtime voice changing. It is an explicit Signals and
Systems laboratory path, not an always-on voice effect.

## 4. Concrete project architecture after the upgrade

```text
Dashboard controls
    │
    ├── Live Studio ──> buildRealtimeConfig
    │                  └──> runRealtimeVoiceChanger
    │                       └──> processAudioFrame (single realtime DSP core)
    │
    ├── AM Lab ───────> runAMExperiment
    │                  └──> applyModDemod (shared AM implementation)
    │
    └── File Studio ──> processAudioFile
                       or processAudioFileHighQuality
```

This preserves one processing truth for each algorithm while allowing the Dashboard to add
routing, interaction, telemetry and visualization.

## 5. Source set reviewed

Primary project/research sources reviewed during the upgrade included:

- w-okada/voice-changer (VCClient)
- RVC-Project/Retrieval-based-Voice-Conversion-WebUI
- Plachtaa/seed-vc and its realtime GUI implementation
- IAHispano/Applio and release notes
- yxlllc/DDSP-SVC
- svc-develop-team/so-vits-svc
- StreamVC paper
- MeanVC 2 paper
- RT-VC paper and project page
- LLVC paper/project
- MathWorks documentation for `audioDeviceReader`, `audioDeviceWriter`,
  `audioPlayerRecorder`, audio I/O buffering/latency, `uigridlayout`, `uidropdown`, and
  `drawnow limitrate`
- Official product pages for Voicemod, Voice.ai, and Altered
