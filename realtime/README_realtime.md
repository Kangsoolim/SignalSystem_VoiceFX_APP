# Realtime Module Notes

This folder is reserved for future realtime audio input/output code.

Current stage only defines the project structure. Do not add microphone loops,
audioDeviceReader/audioDeviceWriter code, or realtime UI callbacks until the
framework interfaces are confirmed.

Realtime mode should call `processAudioFrame` so it shares the same processing
chain as file mode. Realtime filters should avoid `filtfilt`; use realtime-safe
stateful processing such as `filter` or `dsp.FIRFilter` when algorithms are
implemented later.
