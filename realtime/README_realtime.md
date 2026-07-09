# Realtime Voice Processing

## 查看设备

```matlab
listAudioDevices();
```

## 最小运行

```matlab
stats = runRealtimeVoiceChanger(20, 'female');
```

## 指定参数

```matlab
options = struct();
options.sampleRate = 48000;
options.frameLength = 512;
options.intensity = 0.62;
options.enableSpeechClean = true;
stats = runRealtimeVoiceChanger(30, 'female', options);
```

## 调参原则

- 先用 512 samples 跑通并确保 overrun/underrun 为 0；
- 再尝试 256 samples 以降低 buffer latency；
- 若出现 overrun，提高 frameLength 或关闭较重模块；
- MATLAB 统计的 `meanProcessMs` 是算法处理耗时，不等于麦克风到耳机的完整 round-trip latency；
- Windows 追求更低 I/O 延迟时，可进一步评估兼容的 ASIO 全双工设备链。

实时模式必须继续调用 `processAudioFrame`，不要在 App callback 中另写一套变声算法。
