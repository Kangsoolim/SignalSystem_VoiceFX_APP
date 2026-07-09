# SignalSystem VoiceFX App

一个基于 MATLAB 的语音变声、音效处理与信号可视化 App 原型。项目面向《信号与系统》课程大作业，围绕“音频输入 → 预处理 → 滤波/降噪 → 声线风格化 → 音效与空间处理 → 调制解调 → 时频域可视化”的完整链路，实现了可运行、可测试、可继续扩展的 VoiceFX 工程框架。

本项目重点不是复现声音克隆产品，而是用传统 DSP 与可解释的信号处理方法构建一个完整的语音处理系统。它既可以作为课程实验展示，也可以用于音乐/播客素材的基础音效处理、娱乐变声、匿名采访声线处理演示，以及实时音频处理流程的原型验证。

## 项目定位

VoiceFX App 采用“统一核心处理链 + 文件模式 + 实时模式”的设计：

- **文件模式**：导入本地音频，选择声线、音效、空间效果和 AM 模式，处理后播放、保存，并显示波形、频谱和声谱图。
- **离线高质量模式**：允许使用整段语音上下文，进行声线画像、参数自适应和更稳定的 Pitch/Formant 处理。
- **实时模式**：以逐帧处理为核心，支持麦克风输入、实时声线风格化和运行状态统计，适合课程展示和实时 DSP 原型验证。

## 主要功能

### 1. 音频导入与文件处理

- 支持导入 `wav`、`flac`、`mp3`、`m4a` 等 MATLAB `audioread` 可读取的音频格式；
- 支持一键处理、原音/处理后试听、结果导出；
- 文件模式和实时模式共用核心 frame-level 处理接口，避免维护两套算法逻辑。

### 2. 声线风格化

当前声线模块属于 **source-aware adaptive DSP voice styling**。系统会根据输入语音的 F0、能量、频谱和动态特征进行声线画像，并映射到较保守的目标风格参数。

支持的声线方向包括：

- 深沉男声；
- 柔和女声；
- 明亮童声；
- 稳定老年声；
- 匿名化/采访风格；
- 机器人风格。

这些模式用于“风格化变声”和信号处理展示，不等同于特定真人目标音色复刻，也不是 neural zero-shot voice cloning。

### 3. 音效与空间效果

系统支持多种可组合处理：

- 电话音、广播音、Lo-fi、Bitcrusher、留声机、机器人音效；
- Delay、Bathroom、Cave 等空间效果；
- 声线、音效和空间效果可以串联组合，例如“深沉男声 + 电话音”“柔和女声 + Lo-fi”“童声 + 混响”等。

这类功能可用于课程演示，也可用于简单的创意音频、短视频配音、娱乐变声和音乐素材预处理。

### 4. 滤波、降噪与 AM 调制解调

项目包含基础滤波和课程相关信号处理模块：

- 高通、低通、带通、50 Hz 陷波、语音增强滤波；
- `speech_clean` 低复杂度语音清理基线；
- AM 调制与解调，用于观察频谱搬移、包络变化和解调恢复过程；
- 波形、频谱、声谱图等可视化结果，便于写入实验报告和进行信号分析。

## 处理链结构

实时和文件处理共享核心链路：

```text
Audio Input
  -> preprocessAudio
  -> addNoise
  -> applyDenoiseFilter
  -> applyVoiceStyle
  -> applyVocalFX
  -> applySpaceFX
  -> applyModDemod
  -> safeLimiter
  -> Playback / Save / Visualization
```

核心帧接口为：

```matlab
[yFrame, state] = processAudioFrame(xFrame, fs, config, state);
```

离线高质量处理入口为：

```matlab
[y, state, diagnostics] = processAudioFileHighQuality(x, fs, config);
```

实时模式入口为：

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

## App 启动方法

在 MATLAB 中打开本仓库根目录后运行：

```matlab
addpath(genpath(pwd))
launchVoiceFXApp
```

App 启动后，可以选择示例音频或导入本地音频，再选择推荐预设或手动配置处理链。

## 推荐测试

在 MATLAB Current Folder 切到仓库根目录后运行：

```matlab
addpath(genpath(pwd));
run('tests/run_voice_core_suite.m');
```

也可以先运行基础测试：

```matlab
run('tests/test_00_framework_smoke.m');
run('tests/test_10_run_file_mode.m');
run('tests/test_11_app_backend_config.m');
```

## 目录结构

```text
app/        App 启动入口、界面逻辑与 App 配置
core/       统一处理链、文件模式、预处理、限幅和默认配置
modules/    声线、滤波、音效、空间、调制解调和可视化模块
realtime/   实时麦克风处理入口和设备相关函数
scripts/    图像导出、样本验证和报告素材生成脚本
tests/      回归测试和模块测试
docs/       架构说明和工程边界文档
samples/    示例音频
```

## 应用价值

本项目的价值主要体现在三个方面：

1. **课程实验展示**：把信号与系统中的滤波、调制解调、频谱分析、时频可视化等知识串成一个完整 App；
2. **创意音频处理原型**：为歌曲片段、配音、播客或短视频素材提供基础声线风格化和音效处理；
3. **实时 DSP 工程练习**：通过 frame-based processing、状态连续、实时 I/O、处理耗时统计等模块，展示从离线算法到实时音频系统的工程过渡。
