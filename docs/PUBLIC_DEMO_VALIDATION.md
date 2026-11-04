# 公开演示样本维护验证记录

本次只整理公开样本、默认路径、报告标签、样本格式检查和说明；
`core/`、`modules/`、`app/`、`realtime/` 中的算法、接口及处理顺序均未修改。
四段私人输入从本次修改的文件树移除，未复制或用来生成替代样本。
Git 历史未重写；旧提交仍包含私人录音。只有此修改合并到 `main` 后，
访客在 `main` 最新文件树中才会看到替换结果。

## 已执行的检查

- 全仓库当前文本文件搜索四个旧文件名（包含英文撇号变体）：零残留引用。
- 两个公开样本：Python 标准库 `wave` 检查为单声道 16 kHz / PCM16，
  分别为 268000 / 260320 个采样点，峰值均为 26214（约 0.8），非静音、无截幅。
- FFmpeg 完整解码两个 WAV：均成功，无解码错误。
- `generate_demo_samples.py` 使用固定版本 Flite 成功运行，重复生成的两个文件
  与提交样本字节一致。生成器 Python 语法解析通过。
- 新默认样本路径均存在；App 和批处理仍扫描 `samples/*.wav`，无需写死样本数量。
- MISS_HIT Core 0.9.44 对 8 个修改过的 MATLAB 文件及未改动的
  `scripts/run_sample_batch_validation.m`（共 9 个文件）进行静态语法检查：通过。
  命令使用 `mh_style --no-style --single --input-encoding utf-8 --matlab 2022a`；
  工具最高支持 2022a 语法，此结果不是 MATLAB R2024b 执行验证。
- `git check-ignore --no-index`：两个公开 WAV 可纳入版本控制；私人 WAV/MP3/M4A
  及 `results/` 中的新音频、CSV 结果均被忽略。忽略规则不阻止 `git add -f`，
  也不会移除历史提交中的文件。
- `git diff --check`：通过；核心目录无改动。

样本 SHA-256：

```text
280e03b5336bfb1309d78e796f9301b13de5dfe9ccb8a0cab64c2ef2cbced9ee  demo_speech.wav
bc480face71a9e4c7afd756a9369b48e551482687c616429ee767a3473b913ad  demo_speech_alt.wav
```

## 未运行的 MATLAB 检查

当前云环境无 MATLAB，本次未运行任何 MATLAB 测试，不声称它们通过。
尚未验证批处理生成结果、自然度/变声听感、App 交互、Audio Toolbox 的 HQ 路径和实时 I/O。
合成语音不能替代这些功能测试或人工听辨。

有 MATLAB R2024b 时，可在项目根目录按需运行：

```matlab
addpath(genpath(pwd));
run('tests/test_00_framework_smoke.m');
run('tests/test_08_sample_batch_validation.m');
run('tests/test_09_preprocess_validation.m');
run('tests/test_10_run_file_mode.m');
run('tests/test_11_app_backend_config.m');
run('tests/run_voice_core_suite.m');
run_adaptive_voice_audition([], 'female');
run_v25_first_round_audition();
run_v25_noise_denoise_demo();
export_stage3_sample_audition();
export_stage5_space_validation();
run('scripts/export_report_figures.m');
```

App 与实时麦克风仍需在支持的桌面和音频设备上单独测试。
项目进度表在当前仓库及其父目录中不存在，且基线提交记录了删除；
遵循不擅自重建用户删除内容的约定，本次未新建或更新进度表，未填写人工验证状态。
