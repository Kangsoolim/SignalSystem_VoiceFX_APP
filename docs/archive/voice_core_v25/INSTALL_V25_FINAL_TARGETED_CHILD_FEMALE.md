# V2.5 最终定向优化：童声 + 低音男声转女声

## 目标

这一包只处理两个问题，不再改男声、老人声、加噪、VAD去噪、AM、结果保存和批处理逻辑：

1. `child_bright_soft`：增加明显的幼态/儿童感，同时保留源语速、停顿和音高轮廓；
2. `female_gentle_sweet`：低F0来源获得足够的上移和有限的频谱包络变化，避免“基本还是男声”。

## 安装

把补丁根目录中的全部内容复制到：

`本仓库根目录`

Windows 选择：

- 合并文件夹
- 替换同名文件

不要删除原项目，不要重新 `git init`。

## MATLAB 最终测试

```matlab
% 在 MATLAB 中打开本仓库根目录后运行：
addpath(genpath(pwd));
clear functions;
rehash;

run('tests/run_v25_final_suite.m');
```

目标最后一行：

```text
ALL V2.5 TARGETED FINAL TESTS PASSED.
```

## 先看参数规划

```matlab
report = run_v25_source_diagnostics('你的文件.wav');
```

重点看：

- `minimum style shift`
- `style separation applied`
- `pitch shift`
- `formant scale`
- `envelope strength`

## 单个音频四声线试听

```matlab
summary = run_v25_first_round_audition('你的文件.wav');
```

## 批量处理 Voice_test

```matlab
batch = run_v25_batch_four_style();
```

本次结果仍按源文件名和时间戳保存，不覆盖旧结果。

## 技术边界

`child_bright_soft` 保持一个统一的“幼态/儿童感”方向，不声称精确复制某个真实儿童个体或特定角色声线。
这一版仍然是 MATLAB DSP 声线风格转换，不是神经网络零样本说话人克隆。
