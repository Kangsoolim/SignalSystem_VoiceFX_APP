# VoiceFX 语音处理 App

VoiceFX App 是基于 MATLAB programmatic UI 的文件模式语音处理工具。App 负责导入音频、整理处理链配置、调用已有 `core/` 和 `modules/` 后端、播放/保存结果，并显示波形、频谱和声谱图。

## 启动方法

在 MATLAB 中进入项目根目录：

```matlab
cd('C:\Users\13052\Desktop\信号与系统大作业\VoiceFX_App_Project')
addpath(genpath(pwd))
launchVoiceFXApp
```

推荐在项目根目录先运行 `addpath(genpath(pwd))`，再运行 `launchVoiceFXApp`。也可以在 `app/` 目录下运行 `launchVoiceFXApp`，启动脚本会自动定位项目根目录，并加入 `core`、`modules`、`app`、`realtime` 路径。

## 基本使用流程

1. 点击“选择音频”，或从“示例音频”下拉框选择 `samples/` 中的 wav。
2. 选择“推荐预设”，或手动设置噪声、滤波、声线、音效、空间效果和 AM 模式。
3. 点击“处理音频”。
4. 在右侧查看波形、频谱和处理后声谱图。
5. 点击“播放原音”或“播放处理后”试听。
6. 点击“停止播放”可停止当前音频；点击“保存结果”可导出处理后的 wav。

## 当前支持

- 文件导入：wav、flac、mp3、m4a，具体格式取决于 MATLAB `audioread` 支持情况。
- 文件模式处理：通过 `core/runFileMode.m` 调用 `preprocessAudio` 和 `processAudioFile`。
- 预设组合：原声清理、男声 + 电话音、儿童声线 + Reverb、老年声线 + 留声机、匿名采访 + 对讲机、Robot + Bitcrusher、山洞广播。
- 手动处理链：噪声、滤波、声线风格、音效、空间效果、AM 模式。
- 播放：使用 `audioplayer`，支持原音和处理后音频。
- 保存：使用 `uiputfile` 和 `audiowrite`，不会覆盖原始输入文件。
- 图像：App 内 `uiaxes` 显示波形、频谱和处理后声谱图；长音频会降采样或限制显示长度。

## 实时模式状态

实时模式当前为实验性/占位入口。第一版 App 优先保证文件模式稳定，不启动实时音频循环，也不依赖实时工具箱功能。实时处理后续若启用，应避免在实时循环中使用 `filtfilt`，也不要频繁刷新复杂图像。

## 常见问题

- 无声音：确认系统音量、MATLAB 音频设备、当前音频不是静音；也可以先播放原音确认导入正常。
- 工具箱缺失：部分滤波或声谱图函数可能依赖 Signal Processing Toolbox。后端已有基础 fallback，App 也包含简化声谱图 fallback。
- `shiftPitch` 不存在：声线模块会自动使用后备近似方案，效果不如专用函数自然，但不会阻止文件模式运行。
- 图像慢：长音频绘图会降采样，声谱图默认只显示处理后前 30 秒；如果仍然较慢，可先用较短 samples 测试。
- AM 模式声音异常：AM 是信号与系统演示功能，主要用于观察调制/解调和频谱移动，不一定适合作为常规人声美化效果。

