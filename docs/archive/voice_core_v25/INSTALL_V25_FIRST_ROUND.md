# V2.5 第一轮整包修改说明

本包基于用户上传的当前 V2 仓库直接修改，只处理本轮约定的三个重点：

1. 四声线变声核心
   - `male_deep_gentle`：低沉温柔男声
   - `female_gentle_sweet`：温柔甜美女声
   - `child_bright_soft`：清亮柔和童声
   - `elder_warm_steady`：温暖沉稳老人声
   - 保留 `male` / `female` / `child` / `elder` 旧别名兼容。

2. VAD 感知去噪
   - 高通去低频轰鸣
   - 工频及谐波窄陷波
   - 能量 + 频谱平坦度 + 过零率的语音概率估计
   - 8 频带分解
   - VAD 控制噪声更新速度
   - Wiener-like 增益
   - Attack / Release 平滑
   - 有限 RMS 补偿

3. 加噪升级
   - `white`
   - `pink`
   - `powerline_hum`（兼容 `hum50` / `hum60`）
   - `impulse_keyboard`（兼容 `impulse`）
   - `babble_crowd`（synthetic babble-like）
   - SNR 控制、固定 seed 可复现、跨帧状态连续

## 安装

将补丁包中的目录按原有相对路径覆盖到当前仓库根目录：

`本仓库根目录`

不要删除 `.git`，不要重新初始化仓库。

## MATLAB 验证顺序

```matlab
% 在 MATLAB 中打开本仓库根目录后运行：
addpath(genpath(pwd));
clear functions;
rehash;
run('tests/run_v25_first_round_suite.m');
```

若通过，再生成同源四声线试听：

```matlab
summary = run_v25_first_round_audition();
```

也可以指定自己的 WAV：

```matlab
summary = run_v25_first_round_audition('D:\voice_test\my_voice.wav');
```

输出目录：

`results/audio/v25_first_round/`

## 重要说明

- 本轮没有接 Seed-VC、RVC 或 Python 训练环境。
- 四声线核心仍属于 MATLAB DSP / source-filter-inspired baseline，不是神经说话人克隆。
- 自动测试只能验证数值安全、状态连续、参数方向和场景可复现；最终声线是否达到“低沉温柔、温柔甜美、清亮柔和、温暖沉稳”必须通过同一个真人源音频的人工试听继续调参。
- 本轮修改已经进行 MATLAB 语法树静态解析检查；实际 MATLAB R2025b 运行仍需在用户电脑上执行上述测试。

## 加噪/去噪试听

```matlab
info = run_v25_noise_denoise_demo([], 'babble_crowd');
```

输出目录：`results/audio/v25_noise_denoise/`。
