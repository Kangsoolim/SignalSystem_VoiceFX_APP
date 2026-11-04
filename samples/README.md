# Public demonstration speech

本目录仅提供非个人的英文合成语音。没有使用、转换或派生项目作者的私人录音，
也没有下载真人音频、歌曲或受限的在线 TTS 输出。

| 文件 | 生成声线 | 格式 | 时长 |
| --- | --- | --- | --- |
| `demo_speech.wav` | CMU Flite `slt` | 单声道 16 kHz / 16-bit PCM WAV | 约 16.75 秒 |
| `demo_speech_alt.wav` | CMU Flite `rms` | 单声道 16 kHz / 16-bit PCM WAV | 约 16.27 秒 |

## 来源与许可

- 引擎：Carnegie Mellon University 的 [Flite 2.2](https://github.com/festvox/flite/tree/v2.2)，
  固定源码提交 `e9e2e37c329dbe98bfeb27a1828ef9a71fa84f88`。
- 声线：该发布内置的 `cmu_us_slt` 和 `cmu_us_rms`，没有额外下载模型。
  它们是公开许可的 TTS 声线，不代表未使用过人声训练资料，也不代表项目作者的声音。
- 许可依据：Flite 发布集合及上述声线使用允许使用、修改和再分发的 CMU BSD 风格许可。
  上游完整许可与第三方声明保留在 [LICENSE-Flite.txt](LICENSE-Flite.txt)，
  对应上游 [COPYING](https://github.com/festvox/flite/blob/e9e2e37c329dbe98bfeb27a1828ef9a71fa84f88/COPYING)。
  分发本目录的样本时请一并保留这些声明；不得以原作者名义为衍生产品背书。
- 朗读文本是本次维护新编写的中性测试句，见同名 `.txt` 文件；生成语音作为公开演示素材提供，
  沿用上述允许使用、修改、再分发的许可条件，不改变仓库其他文件的许可。
- 生成时对 Flite 原始输出进行了峰值归一化（0.8），没有混入其他音频。

## 可复现生成（可选）

普通访客直接使用已提交的两个 WAV 即可，MATLAB 不需要 Python 或 Flite。
只有重新生成样本时才需要 Python 3、C 编译器、GNU Make 和 Flite。
本次生成环境为 Linux，使用下列固定版本源码；不同编译器或平台的浮点实现可能导致
WAV 的字节哈希不同。以下生成器不读取任何输入录音，不联网、不使用 Python 第三方包。

在仓库之外的临时构建目录执行：

```sh
git clone --branch v2.2 --depth 1 https://github.com/festvox/flite.git flite
cd flite
git rev-parse HEAD # 应为 e9e2e37c329dbe98bfeb27a1828ef9a71fa84f88
./configure --with-audio=none
# Git 源码包需要先生成 voice list；串行构建避免生成文件竞态。
(cd main && ../tools/make_voice_list cmu_us_slt cmu_us_rms)
make -j1
```

回到本仓库根目录，指定刚才编译的可执行文件：

```sh
python3 scripts/generate_demo_samples.py --flite /absolute/path/to/flite/bin/flite
```

可加 `--output-dir /temporary/output` 进行复现检查而不覆盖已提交样本。
`demo_speech.txt` 使用 `slt`，`demo_speech_alt.txt` 使用 `rms`；生成器调用
`flite -voice <voice> -f <text> -o <wav>`，保留采样率，归一化为单声道 PCM16 WAV。

## 使用与限制

App 的示例列表及批处理脚本自动扫描 `samples/*.wav`；默认声线试听和报告导出
使用这里的公开语音。需要自定义语音时，可给 `run_adaptive_voice_audition`、
`run_v25_first_round_audition` 或 `run_v25_noise_denoise_demo` 传入合法音频路径，
也可用 App 导入仓库外的文件。

这些样本含有元音、辅音、停顿和音高变化，适合演示基础声线、滤波、噪声和空间效果。
它们不能完全替代真实自然语音、演唱、自然度/身份相似度评估或实时麦克风测试。
更全面的测试请使用自己合法持有的语音，并在本地人工听辨；不要提交私人录音或其处理结果。
