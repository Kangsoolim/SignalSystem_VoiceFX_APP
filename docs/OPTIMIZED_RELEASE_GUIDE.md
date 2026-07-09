# Optimized Voice Core Release Guide

## 本版本解决的问题

- 修复旧版 fractional-delay 可能产生 MATLAB `buffer(0)` 的索引错误；
- 删除每短帧重启 Pitch Shift 的思路，实时引擎使用跨帧连续 state；
- 新增高质量离线引擎，避免把低延迟算法强行当作最佳文件处理算法；
- 声线分析从单个 F0 扩展为 Pitch / Energy / Rhythm Proxy / Spectrum / Optional Formant 多组画像；
- 自适应参数加入置信度、F0 稳定度、用户强度和频谱亮度的有界映射；
- 预处理加入防反相抵消的 mono downmix、finite cleanup 和 emergency peak protection；
- 新增 speech_clean：低频 rumble、工频谐波、多频带平滑 Wiener-like 控制；
- soft limiter 改为线性区 + 单调 soft knee，不再对安全区间全部染色；
- 新增可复用 target reference profile：同一目标画像可适配不同 source 用户；
- 新增实时设备列表、实时麦克风链和 overrun/underrun/RTF 统计；
- 新增压力测试、索引 wrap 测试、连续性测试、speech_clean 测试和离线 HQ 测试。

## 安装方式

这是覆盖包，不要删除自己的 `.git`。

将 patch ZIP 解压后，把其中的 `core/`、`modules/`、`scripts/`、`tests/`、`realtime/`、`docs/` 和 `README.md` 覆盖到：

```text
D:\Projects\SignalSystem_VoiceFX_APP
```

## MATLAB 测试

```matlab
cd('D:\Projects\SignalSystem_VoiceFX_APP');
addpath(genpath(pwd));
clear functions;
rehash;

run('tests/test_00_framework_smoke.m');
run('tests/test_01_preprocess_limiter.m');
run('tests/run_voice_core_suite.m');
```

## 试听

```matlab
info = run_adaptive_voice_audition([], 'female');
```

重点比较：

```text
*_02_realtime_dsp.wav
*_03_offline_hq.wav
```

前者验证实时兼容路径，后者用于文件模式高质量结果。

## 实时

```matlab
listAudioDevices();
stats = runRealtimeVoiceChanger(20, 'female');
```

第一次运行时使用耳机，避免麦克风-扬声器声学反馈。

## Git 提交建议

全部测试和试听通过后：

```bash
git status
git add core modules scripts tests realtime docs README.md
git commit -m "feat: rebuild adaptive voice core and realtime audio pipeline"
git push -u origin feature/voice-conversion-core
```
