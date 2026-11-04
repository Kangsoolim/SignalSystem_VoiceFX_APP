# SignalSystem VoiceFX APP

面向《信号与系统》课程项目的 MATLAB 人声处理与实时变声工程。当前仓库是包含文件处理、声线分析、自适应 DSP 变声、滤波/降噪、音效、空间效果、调制解调、自动测试和实时音频 I/O 的可继续开发版本。

## 当前核心能力

- 统一帧接口：`[yFrame, state] = processAudioFrame(...)`
- 文件模式：`processAudioFile`
- 高质量离线文件模式：`processAudioFileHighQuality`
- 源声线画像：F0 分布、音域、能量、动态、停顿/节奏代理、频谱特征、可选 LPC 共振峰估计
- 源声线感知参数映射：`adaptVoiceStyleConfig`
- 可复用目标参考声线画像：同一 target profile 可对不同 source 用户生成不同自适应参数
- 实时兼容 DSP 变声：连续状态、跨帧 pitch buffer、参数平滑、语音门控、de-esser、响度补偿
- 高质量离线 Pitch 路径：优先调用 MATLAB `shiftPitch` 的 phase locking + formant preservation
- `speech_clean`：因果高通、工频窄陷波、多频带平滑 Wiener-like 增益控制
- 人声音效、空间效果、AM 调制解调与信号可视化
- 麦克风实时链：`realtime/runRealtimeVoiceChanger.m`

## Demonstration / Sample Audio

`samples/demo_speech.wav` 和 `samples/demo_speech_alt.wav` 是非个人的英文 TTS
演示语音，由 CMU Flite 2.2 的 `slt` / `rms` 声线生成，采用单声道、16 kHz、
16-bit PCM WAV。来源、开放许可、朗读文本和可复现生成步骤见
[samples/README.md](samples/README.md)。播放或处理已提交的 WAV 不需要安装 TTS。

在 MATLAB 中将 Current Folder 切到仓库根目录后：

```matlab
addpath(genpath(pwd));
info = run_adaptive_voice_audition([], 'female'); % 默认使用 demo_speech.wav
% 或启动 App，在“示例音频”中选择公开样本：
launchVoiceFXApp;
% 批量处理 samples/ 中的 WAV（生成结果写入 results/）：
run('scripts/run_sample_batch_validation.m');
```

合成语音可用于处理链、滤波、降噪与音效演示，不能完全替代自然人声、演唱、
实时设备或人工听感测试。更完整的效果验证可导入自己合法持有的 WAV，例如
`run_adaptive_voice_audition('D:/audio/my_speech.wav', 'female')`，也可通过 App 选择文件。
请将私人输入保留在仓库外；`.gitignore` 仅允许两段已审查的公开 WAV，并忽略生成结果。
新增公开样本前需单独核对再分发许可并更新忽略规则。

本次整理仅移除当前版本中的私人样本，不清理 Git 历史；旧提交仍可能包含原录音。

## 两套声线处理引擎

### 1. Realtime DSP Engine

适合麦克风实时处理：

```text
microphone frame
  -> preprocessAudio
  -> speech_clean
  -> source-aware calibration
  -> stateful pitch shift
  -> timbre shaping / de-essing
  -> vocal FX / space FX
  -> limiter
  -> speaker
```

调用：

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

### 2. Offline HQ Engine

适合导入音频文件、试听与导出。完整语句先进行声线画像，然后优先使用 Audio Toolbox 的 phase locking + formant preservation Pitch Shift：

```matlab
[y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);
```

对比试听：

```matlab
info = run_adaptive_voice_audition([], 'female');
```

输出：

```text
results/audio/adaptive_voice_v5/
  *_00_original.wav
  *_01_speech_clean.wav
  *_02_realtime_dsp.wav
  *_03_offline_hq.wav
```

## 推荐测试顺序

MATLAB Current Folder 切到仓库根目录，然后：

```matlab
addpath(genpath(pwd));
run('tests/run_voice_core_suite.m');
```

也建议先运行基础回归测试：

```matlab
run('tests/test_00_framework_smoke.m');
run('tests/test_01_preprocess_limiter.m');
run('tests/test_06_voice_style_and_chain.m');
```


## 目标参考声线画像

构建一次目标参考画像：

```matlab
out = build_target_voice_profile('target_reference.wav');
loaded = load(out.outputPath);
config.voice.params.targetProfile = loaded.targetProfile;
```

这会让同一目标画像面对不同用户时生成不同的 F0/频谱自适应参数。

## 实时设备

查看设备：

```matlab
listAudioDevices();
```

运行 20 秒女声模式：

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

实时链输出统计包括平均处理耗时、P95 处理耗时、RTF、overrun 和 underrun。注意：处理耗时不是声卡完整往返延迟。

## 工程边界

当前 MATLAB 声线引擎属于 **source-aware adaptive DSP voice styling**，可以支持 male / female / child / elder / anonymous / robot_voice 等风格化，并用于实时信号处理课程展示；它不是“任意真人目标音色克隆”。

专业级任意目标声线产品的下一阶段需要在现有 App-facing interface 后加入 StreamVC、RT-VC、MeanVC 2、X-VC 等神经 Voice Conversion 路线，并保留当前 DSP 引擎作为低资源模式、故障回退和基线。

详细研究与工程边界见：`docs/VOICE_CORE_RESEARCH_NOTES.md`。
