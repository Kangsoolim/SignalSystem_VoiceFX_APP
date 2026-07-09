# VoiceFX Architecture

## 1. 总体目标

仓库采用“统一核心处理链 + 两种运行模式”的结构：

- **实时模式**：严格因果、逐帧、状态连续；
- **离线高质量模式**：允许整句上下文和更高质量 Pitch/Formant 处理。

App Designer 只负责 UI、参数和状态展示，不在回调中重复 DSP 算法。

## 2. 实时统一处理链

```text
preprocessAudio
  -> addNoise
  -> applyDenoiseFilter
  -> applyVoiceStyle
  -> applyVocalFX
  -> applySpaceFX
  -> applyModDemod
  -> safeLimiter
```

入口：

```matlab
[yFrame, state] = processAudioFrame(xFrame, fs, config, state);
```

所有跨帧信息必须放进 `state`，包括：

- IIR filter state
- speech_clean noise/gain state
- pitch circular buffer / phase
- calibration buffer / source profile
- pitch target smoothing
- speech gate / wet ramp
- de-esser gain
- RMS compensation
- FX and space buffers

## 3. 离线高质量处理链

```text
full-file preprocessing
  -> frame-continuous noise/filter
  -> processVoiceFileHQ (whole utterance)
  -> frame-continuous FX/space/mod-demod
  -> safeLimiter
```

入口：

```matlab
[y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);
```

`processVoiceFileHQ` 优先使用：

```text
Source profile
  -> adaptive parameter mapping
  -> phase-locked pitch shift
  -> formant preservation
  -> conservative timbre shaping
  -> de-essing
  -> limited RMS matching
  -> soft limiter
```

当 `shiftPitch` 不可用时，不采用会产生明显伪影的“短帧循环重采样”伪实现，而是安全地旁路 Pitch 层并保留 timbre 层，同时在 diagnostics 中明确记录 fallback。

## 4. 声线画像与自适应映射

```text
calibration utterance
  -> analyzeVoiceProfile
      - F0 distribution / pitch range
      - voiced ratio / harmonicity proxy
      - RMS / dynamic range / crest factor
      - activity / pause / rhythm proxies
      - spectral centroid / spread / rolloff / flatness
      - low-mid-high energy ratios
      - optional LPC formants
  -> adaptVoiceStyleConfig
      - engineering preset OR reusable target reference profile
      - bounded target F0 region
      - confidence factor
      - stability factor
      - intensity factor
      - brightness correction
      - conservative pitch/timbre parameters
```

这不是把口音、咬字、内容等信息简化成几个 DSP 数值；这些更高层因素需要后续神经内容/发音表征模块处理。

## 5. speech_clean

`applyDenoiseFilter(..., mode='speech_clean')` 的当前实现是低复杂度 DSP 基线：

1. 因果低阶高通抑制 DC/rumble；
2. 50/100/... Hz 窄陷波抑制工频及谐波；
3. 4 个宽频带分解；
4. 时间平滑的噪声功率估计；
5. Wiener-like band gain；
6. attack/release 平滑，避免独立帧硬门限导致 musical noise；
7. 仅有限 ±1.5 dB 的缓慢补偿。

它借鉴“感知分带 + 时间上下文”的工程原则，但不是 DeepFilterNet 的复现，也不应如此表述。

## 6. 实时音频

入口：

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

建议在第一轮使用 48 kHz / 512 samples，稳定后再尝试 256 samples。减小 frame size 会降低缓冲延迟，但更容易 overrun，因此必须监测：

- meanProcessMs
- p95ProcessMs
- meanRealtimeFactor
- totalOverrunSamples
- totalUnderrunSamples

## 7. 长期 AI VC 接口

当前 DSP Engine 与未来 AI VC Engine 应并列：

```text
App / Audio Router
  -> VoiceEngine interface
       -> Adaptive DSP Engine
       -> Neural VC Engine
            -> causal content/articulatory representation
            -> source prosody conditioning
            -> target timbre representation
            -> streaming conversion model
            -> DDSP/neural vocoder
```

这样不需要推翻 App、音频 I/O、Git 协作和测试框架。
