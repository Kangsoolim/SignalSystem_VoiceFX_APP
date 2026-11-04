%EXPORT_REPORT_FIGURES Export report-ready figures and wav files from public synthetic speech samples.
%   Run from project root:
%       addpath(genpath(pwd));
%       run('scripts/export_report_figures.m');

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

runStarted = datetime('now');
timestamp = datestr(runStarted, 'yyyymmdd_HHMMSS');
outputRoot = fullfile(projectRoot, 'results', ['report_figures_', timestamp, '_voice_compare_fix']);
if exist(outputRoot, 'dir') == 7
    suffix = 1;
    while exist([outputRoot, sprintf('_%02d', suffix)], 'dir') == 7
        suffix = suffix + 1;
    end
    outputRoot = [outputRoot, sprintf('_%02d', suffix)];
end
figureDir = fullfile(outputRoot, 'figures');
wavDir = fullfile(outputRoot, 'wav');
manualDir = fullfile(outputRoot, 'screenshots_manual');
ensureDir(outputRoot);
ensureDir(figureDir);
ensureDir(wavDir);
ensureDir(manualDir);

fontName = chooseReportFont();
setReportGraphicsDefaults(fontName);
global REPORT_FIGURE_BOX_GLYPH_DETECTED REPORT_FIGURE_TEXT_MODE REPORT_FIGURE_FONT
REPORT_FIGURE_BOX_GLYPH_DETECTED = false;
REPORT_FIGURE_TEXT_MODE = 'English fallback';
REPORT_FIGURE_FONT = fontName;

baseConfig = makeReportConfig();
manifestRows = {};
failures = {};
skipped = {};
sampleFilesUsed = {};
pngCount = 0;
wavCount = 0;
voiceSinglePngCount = 0;
voiceOverviewPngCount = 0;
voiceWavCount = 0;

samplesDir = fullfile(projectRoot, 'samples');
samplePaths = struct();
samplePaths.speech = fullfile(samplesDir, 'demo_speech.wav');
samplePaths.speechAlt = fullfile(samplesDir, 'demo_speech_alt.wav');

requiredSamples = {samplePaths.speech; samplePaths.speechAlt};
for k = 1:numel(requiredSamples)
    if exist(requiredSamples{k}, 'file') ~= 2
        msg = ['缺失样本文件: ', requiredSamples{k}];
        fprintf(2, '%s\n', msg);
        failures{end+1,1} = msg; %#ok<SAGROW>
    else
        sampleFilesUsed{end+1,1} = requiredSamples{k}; %#ok<SAGROW>
    end
end

fprintf('Report figure export started: %s\n', char(runStarted));
fprintf('Output root: %s\n', outputRoot);

% 1. Public synthetic speech overview.
try
    fileName = '公开合成语音_波形概览.png';
    figPath = fullfile(figureDir, fileName);
    sampleList = {
        'Synthetic speech', 'demo_speech.wav', samplePaths.speech
        'Synthetic speech alternate', 'demo_speech_alt.wav', samplePaths.speechAlt
    };
    fig = figure('Visible', 'off', 'Color', 'w', 'Name', '公开合成语音波形概览');
    tiledlayout(fig, size(sampleList, 1), 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    for k = 1:size(sampleList, 1)
        [x, fs] = readMonoAudio(sampleList{k, 3}, baseConfig);
        x = limitDuration(x, fs, 10.0);
        x = normalizeAudio(x, 0.95);
        t = (0:numel(x)-1).' / fs;
        nexttile;
        plot(t, x, 'Color', reportColor(k), 'LineWidth', 0.75);
        grid on;
        xlabel('Time / s');
        ylabel('Normalized amplitude');
        title(sprintf('%s - %s', sampleList{k, 1}, sampleList{k, 2}), 'Interpreter', 'none');
        ylim([-1.05 1.05]);
    end
    saveFigure(fig, figPath);
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, '公开合成语音波形概览', ...
        '公开合成语音 samples 音频', 'preprocess', 'overview', '4.1 或 4.2', '', ...
        'A_必须插入', '两个合成语音样本各截取前 10 s 并归一化显示。');
catch err
    failures{end+1,1} = ['公开合成语音波形概览: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, '公开合成语音_波形概览.png', ...
        '公开合成语音波形概览', 'preprocess', 'overview', '4.1 或 4.2', err);
end

% Shared synthetic speech source.
try
    [monoRaw, monoFs] = readMonoAudio(samplePaths.speech, baseConfig);
    monoRaw = limitDuration(monoRaw, monoFs, 10.0);
    monoPre = preprocessForReport(monoRaw, monoFs, baseConfig);
catch err
    monoRaw = [];
    monoPre = [];
    monoFs = 44100;
    failures{end+1,1} = ['合成语音样本读取/预处理失败: ', compactError(err)]; %#ok<SAGROW>
end

% 2. Original vs preprocessed.
try
    requireSignal(monoRaw, '合成语音样本');
    fileName = '合成语音样本_原始音频与预处理后波形频谱对比.png';
    wavName = '合成语音样本_预处理后音频.wav';
    safeWriteWav(fullfile(wavDir, wavName), monoPre, monoFs, baseConfig);
    wavCount = wavCount + 1;
    fig = plotWaveSpectrumCompare(monoRaw, monoPre, monoFs, ...
        '原始合成语音样本', '预处理后合成语音样本', '原始音频与预处理结果对比');
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, '原始音频与预处理结果对比', ...
        'demo_speech.wav', 'preprocess', 'removeDC_normalize_protect', ...
        '4.2', wavName, 'A_必须插入', '预处理包含单声道化、去直流、峰值归一化和安全限幅。');
catch err
    failures{end+1,1} = ['原始音频与预处理后对比: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, '合成语音样本_原始音频与预处理后波形频谱对比.png', ...
        '原始音频与预处理结果对比', 'preprocess', 'removeDC_normalize_protect', '4.2', err);
end

% 3. Three noise modes.
noiseModes = {
    'white', '白噪声', '合成语音样本_白噪声添加结果.wav'
    'hum50', '工频噪声', '合成语音样本_工频噪声添加结果.wav'
    'impulse', '脉冲噪声', '合成语音样本_脉冲噪声添加结果.wav'
};
try
    requireSignal(monoPre, '合成语音样本预处理结果');
    noisySignals = cell(size(noiseModes, 1), 1);
    for k = 1:size(noiseModes, 1)
        y = applyNoiseMode(monoPre, monoFs, noiseModes{k, 1}, baseConfig, k * 101);
        noisySignals{k} = y;
        safeWriteWav(fullfile(wavDir, noiseModes{k, 3}), y, monoFs, baseConfig);
        wavCount = wavCount + 1;
    end
    fileName = '合成语音样本_白噪声工频噪声脉冲噪声波形频谱对比.png';
    fig = plotMultiWaveSpectrum(monoPre, noisySignals, monoFs, ...
        {'原始预处理', noiseModes{1,2}, noiseModes{2,2}, noiseModes{3,2}}, ...
        '三类典型噪声添加结果');
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, '三类典型噪声添加结果', ...
        'demo_speech.wav', 'noise', 'white / hum50 / impulse', ...
        '4.3', strjoin(noiseModes(:,3).', ' | '), 'A_必须插入', ...
        '使用合成语音样本分别添加白噪声、50 Hz 工频噪声和脉冲噪声。');
catch err
    failures{end+1,1} = ['三类典型噪声添加结果: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, '合成语音样本_白噪声工频噪声脉冲噪声波形频谱对比.png', ...
        '三类典型噪声添加结果', 'noise', 'white / hum50 / impulse', '4.3', err);
end

% 4. Denoise before/after.
try
    requireSignal(monoPre, '合成语音样本预处理结果');
    noisyForFilter = applyNoiseMode(monoPre, monoFs, 'hum50', baseConfig, 404);
    denoised = applyFilterMode(noisyForFilter, monoFs, 'notch50', baseConfig);
    wavBefore = '合成语音样本_加噪待滤波音频.wav';
    wavAfter = '合成语音样本_滤波去噪后音频.wav';
    safeWriteWav(fullfile(wavDir, wavBefore), noisyForFilter, monoFs, baseConfig);
    safeWriteWav(fullfile(wavDir, wavAfter), denoised, monoFs, baseConfig);
    wavCount = wavCount + 2;
    fileName = '合成语音样本_加噪语音滤波前后波形频谱对比.png';
    fig = plotWaveSpectrumCompare(noisyForFilter, denoised, monoFs, ...
        '加 50 Hz 工频噪声后', 'notch50 滤波后', '滤波去噪前后对比');
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, '滤波去噪前后对比', ...
        'demo_speech.wav', 'filter', 'hum50 + notch50', ...
        '4.4', [wavBefore, ' | ', wavAfter], 'A_必须插入', ...
        '优先选择工频噪声与 notch50，频谱中 50 Hz 附近抑制最清楚。');
catch err
    failures{end+1,1} = ['加噪语音滤波前后对比: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, '合成语音样本_加噪语音滤波前后波形频谱对比.png', ...
        '滤波去噪前后对比', 'filter', 'hum50 + notch50', '4.4', err);
end

% 5. Filter responses.
try
    fileName = '五类滤波器_幅频响应对比.png';
    fig = plotFilterResponses(monoFs, baseConfig);
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, '不同滤波器幅频响应对比', ...
        'N/A', 'filter', 'highpass / lowpass / bandpass / notch50 / voice_enhance', ...
        '4.4', '', 'A_必须插入', '脚本按 applyDenoiseFilter 的默认参数重新构造等效幅频响应。');
catch err
    failures{end+1,1} = ['五类滤波器幅频响应对比: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, '五类滤波器_幅频响应对比.png', ...
        '不同滤波器幅频响应对比', 'filter', 'responses', '4.4', err);
end

% 6-25. Adaptive voice styles: two synthetic samples x four voice modes.
voiceSamples = {
    'speech', samplePaths.speech, '合成语音样本', 'demo_speech.wav', 'Synthetic speech'
    'speech_alt', samplePaths.speechAlt, '合成语音样本二', 'demo_speech_alt.wav', 'Synthetic speech alternate'
};
voiceModes = {
    'male_deep_gentle', '自适应低沉温和男声', 'Male deep gentle', 'A_必须插入'
    'female_gentle_sweet', '自适应柔和甜美女声', 'Female gentle sweet', 'B_建议插入'
    'child_bright_soft', '自适应明亮柔和童声', 'Child bright soft', 'B_建议插入'
    'elder_warm_steady', '自适应温暖稳定老年声', 'Elder warm steady', 'B_建议插入'
};
voiceInputData = cell(size(voiceSamples, 1), 2);
voiceOutputData = cell(size(voiceSamples, 1), size(voiceModes, 1));
voiceWavNames = cell(size(voiceSamples, 1), size(voiceModes, 1));
for s = 1:size(voiceSamples, 1)
    try
        [voiceRaw, voiceFs] = readMonoAudio(voiceSamples{s, 2}, baseConfig);
        voiceRaw = limitDuration(voiceRaw, voiceFs, 10.0);
        voicePre = preprocessForReport(voiceRaw, voiceFs, baseConfig);
        voiceInputData{s, 1} = voicePre;
        voiceInputData{s, 2} = voiceFs;
    catch err
        failures{end+1,1} = [voiceSamples{s, 3}, '读取/预处理失败: ', compactError(err)]; %#ok<SAGROW>
        voiceInputData{s, 1} = [];
        voiceInputData{s, 2} = 44100;
    end
end

for s = 1:size(voiceSamples, 1)
    for m = 1:size(voiceModes, 1)
        fileName = [voiceSamples{s, 3}, '_', voiceModes{m, 2}, '前后对比.png'];
        wavName = [voiceSamples{s, 3}, '_', voiceModes{m, 2}, '前后对比.wav'];
        captionCn = [voiceSamples{s, 3}, voiceModes{m, 2}, '前后对比'];
        try
            voicePre = voiceInputData{s, 1};
            voiceFs = voiceInputData{s, 2};
            requireSignal(voicePre, [voiceSamples{s, 3}, '预处理结果']);
            mode = voiceModes{m, 1};
            y = processVoiceMode(voicePre, voiceFs, mode, baseConfig);
            voiceOutputData{s, m} = y;
            voiceWavNames{s, m} = wavName;
            safeWriteWav(fullfile(wavDir, wavName), y, voiceFs, baseConfig);
            wavCount = wavCount + 1;
            voiceWavCount = voiceWavCount + 1;
            figTitle = ['Voice style comparison - ', voiceSamples{s, 5}, ' - ', voiceModes{m, 3}];
            fig = plotWaveSpectrumCompare(voicePre, y, voiceFs, 'Original', 'Processed', figTitle);
            saveFigure(fig, fullfile(figureDir, fileName));
            pngCount = pngCount + 1;
            voiceSinglePngCount = voiceSinglePngCount + 1;
            manifestRows = appendManifestRow(manifestRows, fileName, captionCn, ...
                voiceSamples{s, 4}, 'voice_style', mode, '4.5', wavName, ...
                voiceModes{m, 4}, '2x4 voice-style supplementary export; figure text uses English fallback.');
        catch err
            failures{end+1,1} = [captionCn, ': ', compactError(err)]; %#ok<SAGROW>
            manifestRows = appendFailureRow(manifestRows, fileName, captionCn, ...
                'voice_style', voiceModes{m, 1}, '4.5', err);
        end
    end
end

for m = 1:size(voiceModes, 1)
    fileName = [voiceModes{m, 2}, '_公开合成语音横向比较总览.png'];
    captionCn = [voiceModes{m, 2}, '公开合成语音横向比较总览'];
    try
        outputsForMode = voiceOutputData(:, m);
        wavListForMode = voiceWavNames(:, m);
        fig = plotVoiceStyleOverview(voiceInputData, outputsForMode, ...
            voiceSamples(:, 5), voiceModes{m, 3});
        saveFigure(fig, fullfile(figureDir, fileName));
        pngCount = pngCount + 1;
        voiceOverviewPngCount = voiceOverviewPngCount + 1;
        manifestRows = appendManifestRow(manifestRows, fileName, captionCn, ...
            'demo_speech.wav | demo_speech_alt.wav', ...
            'voice_style', voiceModes{m, 1}, '4.5', strjoin(wavListForMode.', ' | '), ...
            'A_必须插入', 'horizontal comparison overview; 2x4 voice-style supplementary export; figure text uses English fallback.');
    catch err
        failures{end+1,1} = [captionCn, ': ', compactError(err)]; %#ok<SAGROW>
        manifestRows = appendFailureRow(manifestRows, fileName, captionCn, ...
            'voice_style', voiceModes{m, 1}, '4.5', err);
    end
end

% Shared alternate synthetic speech source for effects.
try
    [altRaw, altFs] = readMonoAudio(samplePaths.speechAlt, baseConfig);
    altRaw = limitDuration(altRaw, altFs, 10.0);
    altPre = preprocessForReport(altRaw, altFs, baseConfig);
catch err
    altRaw = [];
    altPre = [];
    altFs = 44100;
    failures{end+1,1} = ['合成语音样本二读取/预处理失败: ', compactError(err)]; %#ok<SAGROW>
end

% 10-15. Vocal FX.
fxTasks = {
    'telephone', '合成语音样本二_电话音前后波形频谱对比.png', '合成语音样本二_电话音效果.wav', '电话音音效处理结果', 'A_必须插入'
    'radio', '合成语音样本二_广播音前后波形频谱对比.png', '合成语音样本二_广播音效果.wav', '广播音音效处理结果', 'A_必须插入'
    'bitcrusher', '合成语音样本二_Bitcrusher音效前后波形频谱对比.png', '合成语音样本二_Bitcrusher音效.wav', 'Bitcrusher 音效处理结果', 'B_建议插入'
    'gramophone', '合成语音样本二_留声机音效前后波形频谱对比.png', '合成语音样本二_留声机音效.wav', '留声机音效处理结果', 'A_必须插入'
    'robot', '合成语音样本二_机器人音效前后波形频谱对比.png', '合成语音样本二_机器人音效.wav', '机器人音效处理结果', 'B_建议插入'
    'lofi', '合成语音样本二_LoFi音效前后波形频谱对比.png', '合成语音样本二_LoFi音效.wav', 'Lo-Fi 音效处理结果', 'C_备用'
};
for k = 1:size(fxTasks, 1)
    try
        requireSignal(altPre, '合成语音样本二预处理结果');
        mode = fxTasks{k, 1};
        y = processFxMode(altPre, altFs, mode, baseConfig);
        safeWriteWav(fullfile(wavDir, fxTasks{k, 3}), y, altFs, baseConfig);
        wavCount = wavCount + 1;
        fig = plotWaveSpectrumCompare(altPre, y, altFs, '原始合成语音样本二', ['处理后: ', mode], fxTasks{k, 4});
        saveFigure(fig, fullfile(figureDir, fxTasks{k, 2}));
        pngCount = pngCount + 1;
        note = '使用 demo_speech_alt.wav 的合成语音片段。';
        if strcmp(mode, 'lofi')
            note = [note, ' 备用图，可按报告篇幅选择是否插入。'];
        end
        manifestRows = appendManifestRow(manifestRows, fxTasks{k, 2}, fxTasks{k, 4}, ...
            'demo_speech_alt.wav', 'fx', mode, '4.6', fxTasks{k, 3}, fxTasks{k, 5}, note);
    catch err
        failures{end+1,1} = [fxTasks{k, 4}, ': ', compactError(err)]; %#ok<SAGROW>
        manifestRows = appendFailureRow(manifestRows, fxTasks{k, 2}, fxTasks{k, 4}, ...
            'fx', fxTasks{k, 1}, '4.6', err);
    end
end

% 16-18. Space effects.
spaceTasks = {
    'delay', '合成语音样本_delay空间效果波形频谱声谱图对比.png', '合成语音样本_delay空间效果.wav', 'Delay 空间效果处理结果', 'A_必须插入'
    'bathroom', '合成语音样本_bathroom空间效果波形频谱声谱图对比.png', '合成语音样本_bathroom空间效果.wav', 'Bathroom 空间效果处理结果', 'B_建议插入'
    'cave', '合成语音样本_cave空间效果波形频谱声谱图对比.png', '合成语音样本_cave空间效果.wav', 'Cave 空间效果处理结果', 'B_建议插入'
};
for k = 1:size(spaceTasks, 1)
    try
        requireSignal(monoPre, '合成语音样本预处理结果');
        mode = spaceTasks{k, 1};
        y = processSpaceMode(monoPre, monoFs, mode, baseConfig);
        safeWriteWav(fullfile(wavDir, spaceTasks{k, 3}), y, monoFs, baseConfig);
        wavCount = wavCount + 1;
        fig = plotWaveSpectrumSpectrogramCompare(monoPre, y, monoFs, '原始合成语音样本', ['空间效果: ', mode], spaceTasks{k, 4});
        saveFigure(fig, fullfile(figureDir, spaceTasks{k, 2}));
        pngCount = pngCount + 1;
        manifestRows = appendManifestRow(manifestRows, spaceTasks{k, 2}, spaceTasks{k, 4}, ...
            'demo_speech.wav', 'space', mode, '4.7', spaceTasks{k, 3}, spaceTasks{k, 5}, ...
            '声谱图子图显示处理后拖尾、反射或混响延展。');
    catch err
        failures{end+1,1} = [spaceTasks{k, 4}, ': ', compactError(err)]; %#ok<SAGROW>
        manifestRows = appendFailureRow(manifestRows, spaceTasks{k, 2}, spaceTasks{k, 4}, ...
            'space', spaceTasks{k, 1}, '4.7', err);
    end
end

% 19-20. AM modulation/demodulation.
try
    requireSignal(monoPre, '合成语音样本预处理结果');
    [amBase, amMod, amDemod, amFs, amNotes, amMetrics] = makeAmDemoSignals(monoPre, monoFs, baseConfig);
    amBaseWav = 'AM实验_基带音频.wav';
    amModWav = 'AM实验_调制信号.wav';
    amDemodWav = 'AM实验_解调恢复音频.wav';
    safeWriteWav(fullfile(wavDir, amBaseWav), amBase, amFs, baseConfig);
    safeWriteWav(fullfile(wavDir, amModWav), amMod, amFs, baseConfig);
    safeWriteWav(fullfile(wavDir, amDemodWav), amDemod, amFs, baseConfig);
    wavCount = wavCount + 3;

    fileName = 'AM调制解调_基带调制解调波形恢复对比.png';
    fig = plotAmWaveforms(amBase, amMod, amDemod, amFs, amMetrics);
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    manifestRows = appendManifestRow(manifestRows, fileName, 'AM 调制解调波形恢复结果', ...
        'AM实验测试基带/独白片段', 'modDemod', 'am_modulate + am_demodulate', '4.8', ...
        [amBaseWav, ' | ', amModWav, ' | ', amDemodWav], 'A_必须插入', amNotes);

    fileName = 'AM调制解调_频谱搬移与低通恢复对比.png';
    fig = plotAmSpectra(amBase, amMod, amDemod, amFs, amMetrics);
    saveFigure(fig, fullfile(figureDir, fileName));
    pngCount = pngCount + 1;
    metricNote = sprintf('%s correlation=%.4f; reconstructionSNR=%.2f dB; NMSE=%.6f.', ...
        amNotes, amMetrics.correlation, amMetrics.reconstructionSnrDb, amMetrics.nmse);
    manifestRows = appendManifestRow(manifestRows, fileName, 'AM 调制解调频谱搬移与低通恢复结果', ...
        'AM实验测试基带/独白片段', 'modDemod', 'am_modulate + am_demodulate', '4.8', ...
        [amBaseWav, ' | ', amModWav, ' | ', amDemodWav], 'A_必须插入', metricNote);
catch err
    failures{end+1,1} = ['AM 调制解调导出失败: ', compactError(err)]; %#ok<SAGROW>
    manifestRows = appendFailureRow(manifestRows, 'AM调制解调_基带调制解调波形恢复对比.png', ...
        'AM 调制解调波形恢复结果', 'modDemod', 'am_modulate + am_demodulate', '4.8', err);
    manifestRows = appendFailureRow(manifestRows, 'AM调制解调_频谱搬移与低通恢复对比.png', ...
        'AM 调制解调频谱搬移与低通恢复结果', 'modDemod', 'am_modulate + am_demodulate', '4.8', err);
end

% Manual screenshot placeholders.
manualReadmePath = fullfile(manualDir, 'README_需要人工截图.txt');
manualNames = {
    'VoiceFX_App主界面_文件处理与可视化区域.png'
    'VoiceFX_App处理完成后波形频谱声谱图显示.png'
    'VoiceFX_App保存处理后wav结果截图.png'
    '实时模式_runRealtimeVoiceChanger_stats输出截图.png'
};
writeManualScreenshotReadme(manualReadmePath, manualNames);
for k = 1:numel(manualNames)
    manifestRows = appendManifestRow(manifestRows, manualNames{k}, manualNames{k}, ...
        'N/A', 'manual_screenshot', 'manual', '4.1 / 4.2 / App说明', '', ...
        'B_建议插入', '需人工在 App 或命令行运行后截图补充。');
end
manifestRows = appendManifestRow(manifestRows, 'AM Lab 截图无法自动生成', 'AM Lab 截图替代说明', ...
    'N/A', 'manual_screenshot', 'AM Lab', '4.8', '', 'B_建议插入', ...
    '当前项目没有独立 AM Lab 页面；已用脚本导出的 AM 波形/频谱图替代。');

manifestPath = fullfile(outputRoot, 'figure_manifest.csv');
writeManifestCsv(manifestPath, manifestRows);

readmePath = fullfile(outputRoot, 'README_report_figures.txt');
writeRunReadme(readmePath, runStarted, outputRoot, version, sampleFilesUsed, ...
    pngCount, wavCount, voiceSinglePngCount, voiceOverviewPngCount, ...
    voiceWavCount, fontName, REPORT_FIGURE_TEXT_MODE, ...
    REPORT_FIGURE_BOX_GLYPH_DETECTED, failures, skipped);

fprintf('\n=== report figure export complete ===\n');
fprintf('输出目录完整路径: %s\n', outputRoot);
fprintf('本次新增导出的 png 数量: %d\n', voiceSinglePngCount + voiceOverviewPngCount);
fprintf('本次新增导出的 wav 数量: %d\n', voiceWavCount);
fprintf('8 张声线单图是否全部成功: %s\n', logicalStatus(voiceSinglePngCount == 8));
fprintf('4 张声线横向总览图是否全部成功: %s\n', logicalStatus(voiceOverviewPngCount == 4));
if REPORT_FIGURE_BOX_GLYPH_DETECTED
    fprintf('是否仍检测到方框乱码问题: Box-glyph issue detected in figure text properties\n');
else
    fprintf('是否仍检测到方框乱码问题: No box-glyph issue detected\n');
end
fprintf('总计成功生成的 png 数量: %d\n', pngCount);
fprintf('总计成功生成的 wav 数量: %d\n', wavCount);
if isempty(failures) && isempty(skipped)
    fprintf('失败或跳过的项目: 无\n');
else
    fprintf('失败或跳过的项目:\n');
    for k = 1:numel(failures)
        fprintf('  - %s\n', failures{k});
    end
    for k = 1:numel(skipped)
        fprintf('  - %s\n', skipped{k});
    end
end
fprintf('请查看 figure_manifest.csv 和 README_report_figures.txt。\n');

function config = makeReportConfig()
config = makeDefaultConfig();
config.audio.frameLength = 2048;
config.audio.removeDC = true;
config.audio.normalizeInput = true;
config.audio.normalizeTargetPeak = 0.88;
config.audio.protectInputPeak = true;
config.audio.protectPeak = 0.98;
config.output.limitEnabled = true;
config.output.peakLimit = 0.98;
config.output.limitRange = [-0.98, 0.98];
config.output.limiterMode = 'soft';
config.output.softDrive = 1.15;
config.display.useDb = true;
config.display.dbFloor = -110;
end

function fontName = chooseReportFont()
preferredFonts = {'Microsoft YaHei UI','Microsoft YaHei','SimHei', ...
    'Noto Sans CJK SC','Arial Unicode MS','Arial'};
fontName = 'Arial';
try
    fonts = listfonts;
    for k = 1:numel(preferredFonts)
        if any(strcmpi(fonts, preferredFonts{k}))
            fontName = preferredFonts{k};
            return;
        end
    end
catch
    fontName = 'Arial';
end
end

function setReportGraphicsDefaults(fontName)
set(groot, 'defaultFigureColor', 'w');
set(groot, 'defaultAxesFontName', fontName);
set(groot, 'defaultTextFontName', fontName);
set(groot, 'defaultLegendFontName', fontName);
set(groot, 'defaultAxesFontSize', 10);
set(groot, 'defaultTextInterpreter', 'none');
set(groot, 'defaultAxesTickLabelInterpreter', 'none');
set(groot, 'defaultLegendInterpreter', 'none');
try
    set(groot, 'defaultColorbarFontName', fontName);
catch
end
try
    set(groot, 'defaultColorbarTickLabelInterpreter', 'none');
catch
end
end

function ensureDir(pathName)
if exist(pathName, 'dir') ~= 7
    mkdir(pathName);
end
end

function [x, fs] = readMonoAudio(pathName, config)
if exist(pathName, 'file') ~= 2
    error('exportReportFigures:MissingSample', 'Sample file not found: %s', pathName);
end
[x, fs] = audioread(pathName);
x = double(x);
x(~isfinite(x)) = 0;
if ismatrix(x) && size(x, 2) > 1
    channelRms = sqrt(mean(x .^ 2, 1));
    weightSum = sum(channelRms);
    if weightSum > eps
        x = x * (channelRms(:) / weightSum);
    else
        x = mean(x, 2);
    end
else
    x = x(:);
end
if isfield(config, 'audio') && isfield(config.audio, 'protectPeak')
    protectPeak = min(max(double(config.audio.protectPeak), 0.1), 1.0);
else
    protectPeak = 0.98;
end
peak = max(abs(x));
if peak > protectPeak
    x = x * (protectPeak / peak);
end
end

function y = preprocessForReport(x, fs, config)
y = preprocessAudio(x, fs, config);
y = safeLimiter(y, config);
end

function x = limitDuration(x, fs, maxSeconds)
x = double(x(:));
maxSamples = min(numel(x), max(1, round(maxSeconds * fs)));
x = x(1:maxSamples);
end

function y = normalizeAudio(x, targetPeak)
y = double(x(:));
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > eps
    y = targetPeak * y / peak;
end
end

function safeWriteWav(pathName, x, fs, config)
y = safeLimiter(x, config);
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98 * y / peak;
end
audiowrite(pathName, y, fs);
end

function requireSignal(x, label)
if isempty(x)
    error('exportReportFigures:MissingSignal', '%s is empty or unavailable.', label);
end
end

function y = applyNoiseMode(x, fs, modeName, config, seedValue)
noiseConfig = config.noise;
noiseConfig.enabled = true;
noiseConfig.type = modeName;
noiseConfig.mode = modeName;
noiseConfig.seed = seedValue;
noiseConfig.whiteMode = 'snr';
switch lower(modeName)
    case 'white'
        noiseConfig.snrDb = 14;
        noiseConfig.noiseLevel = 0.025;
    case 'hum50'
        noiseConfig.snrDb = 16;
        noiseConfig.mainsFreq = 50;
        noiseConfig.humNumHarmonics = 5;
    case 'impulse'
        noiseConfig.snrDb = 18;
        noiseConfig.impulseProbability = 0.0022;
        noiseConfig.impulseClickWidthMs = 3.5;
end
[y, ~] = addNoise(x, fs, noiseConfig, initProcessState(config));
y = safeLimiter(y, config);
end

function y = applyFilterMode(x, fs, modeName, config)
filterConfig = config.filter;
filterConfig.enabled = true;
filterConfig.type = modeName;
filterConfig.mode = modeName;
filterConfig.useZeroPhase = true;
if strcmpi(modeName, 'voice_enhance')
    filterConfig.voiceLowCutoff = 95;
    filterConfig.voiceHighCutoff = min(4800, 0.42 * fs);
end
[y, ~] = applyDenoiseFilter(x, fs, filterConfig, initProcessState(config));
y = safeLimiter(y, config);
end

function y = processVoiceMode(x, fs, modeName, config)
cfg = config;
cfg.audio.removeDC = false;
cfg.audio.normalizeInput = false;
cfg.voice.enabled = true;
cfg.voice.type = modeName;
cfg.voice.mode = modeName;
cfg.voice.mix = 1.0;
cfg.voice.intensity = 0.75;
cfg.voice.params.adaptiveEnabled = true;
cfg.voice.params.engine = 'adaptive';
[y, ~, ~] = processAudioFileHighQuality(x, fs, cfg);
y = safeLimiter(y, cfg);
end

function y = processFxMode(x, fs, modeName, config)
cfg = config;
cfg.audio.removeDC = false;
cfg.audio.normalizeInput = false;
cfg.fx.enabled = true;
cfg.fx.type = modeName;
cfg.fx.mode = modeName;
[y, ~] = processAudioFile(x, fs, cfg);
y = safeLimiter(y, cfg);
end

function y = processSpaceMode(x, fs, modeName, config)
cfg = config;
cfg.audio.removeDC = false;
cfg.audio.normalizeInput = false;
cfg.space.enabled = true;
cfg.space.type = modeName;
cfg.space.mode = modeName;
[y, ~] = processAudioFile(x, fs, cfg);
y = safeLimiter(y, cfg);
end

function fig = plotWaveSpectrumCompare(x, y, fs, xLabelText, yLabelText, titleText)
plotSeconds = min(4.0, min(numel(x), numel(y)) / fs);
n = max(1, round(plotSeconds * fs));
xPlot = x(1:min(n, numel(x)));
yPlot = y(1:min(n, numel(y)));
tX = (0:numel(xPlot)-1).' / fs;
tY = (0:numel(yPlot)-1).' / fs;
[fx, mx] = spectrumDb(x, fs);
[fy, my] = spectrumDb(y, fs);

fig = figure('Visible', 'off', 'Color', 'w', 'Name', titleText, 'Position', [100 100 1100 760]);
tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
plot(tX, xPlot, 'Color', [0.10 0.32 0.65], 'LineWidth', 0.75);
grid on; xlabel('Time / s'); ylabel('Amplitude');
title([titleText, ' - ', xLabelText]);
ylim(axisLimitForSignals(xPlot));

nexttile;
plot(tY, yPlot, 'Color', [0.76 0.28 0.14], 'LineWidth', 0.75);
grid on; xlabel('Time / s'); ylabel('Amplitude');
title([titleText, ' - ', yLabelText]);
ylim(axisLimitForSignals(yPlot));

nexttile([1 2]);
plot(fx / 1000, mx, 'Color', [0.10 0.32 0.65], 'LineWidth', 1.0);
hold on;
plot(fy / 1000, my, 'Color', [0.76 0.28 0.14], 'LineWidth', 1.0);
grid on;
xlabel('Frequency / kHz');
ylabel('Magnitude / dB');
title('Spectrum comparison');
legend({xLabelText, yLabelText}, 'Location', 'southwest');
xlim([0, min(8, fs / 2000)]);
ylim([-110 5]);
end

function fig = plotVoiceStyleOverview(inputData, outputsForMode, sampleLabels, modeLabel)
fig = figure('Visible', 'off', 'Color', 'w', 'Name', [modeLabel, ' - Cross-sample comparison'], ...
    'Position', [80 80 1350 1150]);
tiledlayout(fig, size(inputData, 1), 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for s = 1:size(inputData, 1)
    x = inputData{s, 1};
    fs = inputData{s, 2};
    y = outputsForMode{s};
    requireSignal(x, [sampleLabels{s}, ' original']);
    requireSignal(y, [sampleLabels{s}, ' processed']);
    plotSeconds = min(3.5, min(numel(x), numel(y)) / fs);
    n = max(1, round(plotSeconds * fs));
    idx = 1:n;
    t = (idx(:)-1) / fs;

    nexttile;
    plot(t, x(idx), 'Color', [0.10 0.32 0.65], 'LineWidth', 0.70);
    hold on;
    plot(t, y(idx), 'Color', [0.76 0.28 0.14], 'LineWidth', 0.70);
    grid on;
    xlabel('Time / s');
    ylabel('Amplitude');
    title([sampleLabels{s}, ' - Waveform overlay']);
    legend({'Original','Processed'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
    ylim(axisLimitForSignals([x(idx); y(idx)]));

    [fx, mx] = spectrumDb(x, fs);
    [fy, my] = spectrumDb(y, fs);
    nexttile;
    plot(fx / 1000, mx, 'Color', [0.10 0.32 0.65], 'LineWidth', 0.90);
    hold on;
    plot(fy / 1000, my, 'Color', [0.76 0.28 0.14], 'LineWidth', 0.90);
    grid on;
    xlabel('Frequency / kHz');
    ylabel('Magnitude / dB');
    title([sampleLabels{s}, ' - Spectrum overlay']);
    legend({'Original','Processed'}, 'Location', 'southwest');
    xlim([0, min(8, fs / 2000)]);
    ylim([-110 5]);
end
sgtitle([modeLabel, ' - Cross-sample comparison']);
end

function fig = plotMultiWaveSpectrum(original, signals, fs, labels, titleText)
plotSeconds = min(3.0, numel(original) / fs);
n = max(1, round(plotSeconds * fs));
t = (0:n-1).' / fs;
fig = figure('Visible', 'off', 'Color', 'w', 'Name', titleText, 'Position', [100 100 1100 650]);
tiledlayout(fig, 2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
plot(t, original(1:n), 'Color', [0.05 0.05 0.05], 'LineWidth', 0.75);
hold on;
for k = 1:numel(signals)
    s = signals{k};
    nn = min(n, numel(s));
    plot(t(1:nn), s(1:nn), 'Color', reportColor(k), 'LineWidth', 0.70);
end
grid on; xlabel('Time / s'); ylabel('Amplitude');
title([titleText, ' - Waveform overlay']);
legend(labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
ylim([-1.05 1.05]);

nexttile;
[f0, m0] = spectrumDb(original, fs);
plot(f0 / 1000, m0, 'Color', [0.05 0.05 0.05], 'LineWidth', 1.0);
hold on;
for k = 1:numel(signals)
    [f, m] = spectrumDb(signals{k}, fs);
    plot(f / 1000, m, 'Color', reportColor(k), 'LineWidth', 1.0);
end
grid on; xlabel('Frequency / kHz'); ylabel('Magnitude / dB');
title([titleText, ' - Spectrum overlay']);
legend(labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
xlim([0, min(8, fs / 2000)]);
ylim([-110 5]);
end

function fig = plotWaveSpectrumSpectrogramCompare(x, y, fs, xLabelText, yLabelText, titleText)
plotSeconds = min(4.0, min(numel(x), numel(y)) / fs);
n = max(1, round(plotSeconds * fs));
t = (0:n-1).' / fs;
[fx, mx] = spectrumDb(x, fs);
[fy, my] = spectrumDb(y, fs);

fig = figure('Visible', 'off', 'Color', 'w', 'Name', titleText, 'Position', [100 100 1120 820]);
tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
plot(t, x(1:n), 'Color', [0.10 0.32 0.65], 'LineWidth', 0.75);
hold on;
plot(t, y(1:n), 'Color', [0.76 0.28 0.14], 'LineWidth', 0.75);
grid on; xlabel('Time / s'); ylabel('Amplitude');
title([titleText, ' - Waveform comparison']);
legend({xLabelText, yLabelText}, 'Location', 'southoutside', 'Orientation', 'horizontal');
ylim([-1.05 1.05]);

nexttile;
plot(fx / 1000, mx, 'Color', [0.10 0.32 0.65], 'LineWidth', 1.0);
hold on;
plot(fy / 1000, my, 'Color', [0.76 0.28 0.14], 'LineWidth', 1.0);
grid on; xlabel('Frequency / kHz'); ylabel('Magnitude / dB');
title('Spectrum comparison');
legend({xLabelText, yLabelText}, 'Location', 'southwest');
xlim([0, min(8, fs / 2000)]);
ylim([-110 5]);

nexttile;
plotLocalSpectrogram(y(1:n), fs);
title([titleText, ' - Processed spectrogram']);
end

function fig = plotFilterResponses(fs, config)
modes = {'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'};
labels = {'highpass', 'lowpass', 'bandpass', 'notch50', 'voice\_enhance'};
fig = figure('Visible', 'off', 'Color', 'w', 'Name', '不同滤波器幅频响应对比', 'Position', [100 100 1050 650]);
tiledlayout(fig, 2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
hold on;
for k = 1:numel(modes)
    [f, magDb] = equivalentFilterResponse(modes{k}, fs, config);
    plot(f / 1000, magDb, 'Color', reportColor(k), 'LineWidth', 1.1);
end
grid on; xlabel('Frequency / kHz'); ylabel('Magnitude / dB');
title('五类滤波器幅频响应');
legend(labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
xlim([0, min(8, fs / 2000)]);
ylim([-80 8]);

nexttile;
hold on;
for k = 1:numel(modes)
    [f, magDb] = equivalentFilterResponse(modes{k}, fs, config);
    plot(f, magDb, 'Color', reportColor(k), 'LineWidth', 1.1);
end
grid on; xlabel('Frequency / Hz'); ylabel('Magnitude / dB');
title('低频与语音频带细节');
legend(labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
xlim([0, min(5200, fs / 2)]);
ylim([-80 8]);
end

function [f, magDb] = equivalentFilterResponse(modeName, fs, config)
filterConfig = config.filter;
filterConfig.enabled = true;
filterConfig.type = modeName;
filterConfig.mode = modeName;
nyquist = fs / 2;
order = max(1, min(8, round(filterConfig.order)));
switch lower(modeName)
    case 'highpass'
        cutoff = filterConfig.lowCutoff;
        [b, a] = designButterLocal(order, cutoff / nyquist, 'high');
    case 'lowpass'
        cutoff = filterConfig.lowpassCutoff;
        [b, a] = designButterLocal(order, cutoff / nyquist, 'low');
    case 'bandpass'
        lowCutoff = filterConfig.bandpassLowCutoff;
        highCutoff = min(filterConfig.bandpassHighCutoff, nyquist * 0.95);
        [b, a] = designButterLocal(order, [lowCutoff highCutoff] / nyquist, 'bandpass');
    case 'notch50'
        [b, a] = designNotchLocal(filterConfig.notchFreq, filterConfig.bandwidth, fs);
    case 'voice_enhance'
        lowCutoff = filterConfig.voiceLowCutoff;
        highCutoff = min(filterConfig.voiceHighCutoff, nyquist * 0.95);
        [b, a] = designButterLocal(max(2, min(order, 3)), [lowCutoff highCutoff] / nyquist, 'bandpass');
    otherwise
        b = 1; a = 1;
end
nfft = 4096;
if exist('freqz', 'file') == 2
    [h, f] = freqz(b, a, nfft, fs);
else
    h = fft(b, nfft) ./ max(fft(a, nfft), eps);
    f = (0:nfft-1).' * fs / nfft;
    h = h(1:floor(nfft/2)+1);
    f = f(1:floor(nfft/2)+1);
end
magDb = 20 * log10(abs(h) + 1e-12);
end

function [b, a] = designButterLocal(order, normalizedCutoff, kind)
normalizedCutoff = min(max(normalizedCutoff, 1e-5), 0.99999);
if exist('butter', 'file') == 2
    [b, a] = butter(order, normalizedCutoff, kind);
else
    alpha = normalizedCutoff(1);
    switch lower(kind)
        case 'high'
            b = [(1 + alpha) / 2, -(1 + alpha) / 2];
            a = [1, -alpha];
        otherwise
            b = 1 - alpha;
            a = [1, -alpha];
    end
end
end

function [b, a] = designNotchLocal(notchFreq, bandwidth, fs)
bandwidth = max(0.5, abs(double(bandwidth)));
w0 = 2 * pi * notchFreq / fs;
r = 1 - pi * bandwidth / fs;
r = min(max(r, 0.80), 0.9999);
b = [1, -2 * cos(w0), 1];
a = [1, -2 * r * cos(w0), r ^ 2];
dcGain = sum(a) / sum(b);
if isfinite(dcGain) && abs(sum(b)) > eps
    b = b * dcGain;
end
end

function [amBase, amMod, amDemod, fsOut, notes, metrics] = makeAmDemoSignals(monoPre, monoFs, config)
fsOut = min(16000, monoFs);
x = monoPre(:);
if monoFs ~= fsOut
    x = resampleLinearLocal(x, monoFs, fsOut);
end
x = limitDuration(x, fsOut, 1.5);
x = normalizeAudio(x - mean(x), 0.45);
t = (0:numel(x)-1).' / fsOut;
testBase = 0.35 * sin(2*pi*300*t) + 0.22 * sin(2*pi*900*t);
amBase = normalizeAudio(x + testBase, 0.85);
amBase = amBase .* tukeyWindowLocal(numel(amBase), 0.08);

modConfig = config.modDemod;
modConfig.enabled = true;
modConfig.type = 'am_modulate';
modConfig.mode = 'am_modulate';
modConfig.carrierFreq = 4000;
modConfig.modulationIndex = 0.75;
modConfig.messageScale = 0.85;
[amMod, ~, ~] = applyModDemod(amBase, fsOut, modConfig, initProcessState(config));

demodConfig = config.modDemod;
demodConfig.enabled = true;
demodConfig.type = 'am_demodulate';
demodConfig.mode = 'am_demodulate';
demodConfig.carrierFreq = modConfig.carrierFreq;
demodConfig.lowpassCutoff = 1500;
demodConfig.filterOrder = 6;
demodConfig.useZeroPhase = true;
demodConfig.normalizeOutput = true;
[~, amDemod, ~] = applyModDemod(amMod, fsOut, demodConfig, initProcessState(config));

amBase = safeLimiter(amBase, config);
amMod = safeLimiter(amMod, config);
amDemod = safeLimiter(amDemod, config);
metrics = computeRecoveryMetrics(amBase, amDemod);
notes = 'AM 使用独白短片段叠加 300/900 Hz 清晰低频测试基带，便于显示频谱搬移与低通恢复。';
end

function metrics = computeRecoveryMetrics(reference, recovered)
reference = reference(:);
recovered = recovered(:);
n = min(numel(reference), numel(recovered));
reference = reference(1:n) - mean(reference(1:n));
recovered = recovered(1:n) - mean(recovered(1:n));
scale = (recovered' * reference) / max(recovered' * recovered, eps);
aligned = recovered * scale;
err = reference - aligned;
metrics.correlation = (reference' * aligned) / max(sqrt(sum(reference.^2) * sum(aligned.^2)), eps);
metrics.nmse = sum(err.^2) / max(sum(reference.^2), eps);
metrics.reconstructionSnrDb = 10 * log10(max(sum(reference.^2), eps) / max(sum(err.^2), eps));
end

function fig = plotAmWaveforms(baseband, modulated, demodulated, fs, metrics)
n = min(numel(baseband), round(0.055 * fs));
startIndex = min(numel(baseband), max(1, round(0.015 * fs)));
stopIndex = min(numel(baseband), startIndex + n - 1);
idx = startIndex:stopIndex;
t = (idx(:) - idx(1)) / fs;
demodForPlot = matchRmsForPlot(demodulated, baseband);
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'AM 调制解调波形恢复结果', 'Position', [100 100 1050 760]);
tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; plot(t, baseband(idx), 'Color', [0.10 0.32 0.65], 'LineWidth', 0.9);
grid on; xlabel('Time / s'); ylabel('Amplitude'); title('基带信号（独白片段 + 低频测试基带）');
nexttile; plot(t, modulated(idx), 'Color', [0.76 0.28 0.14], 'LineWidth', 0.9);
grid on; xlabel('Time / s'); ylabel('Amplitude'); title('AM 调制信号');
nexttile; plot(t, demodForPlot(idx), 'Color', [0.18 0.55 0.28], 'LineWidth', 0.9);
grid on; xlabel('Time / s'); ylabel('Display amplitude');
title(sprintf('解调恢复信号（corr=%.3f, SNR=%.2f dB, NMSE=%.4g）', ...
    metrics.correlation, metrics.reconstructionSnrDb, metrics.nmse));
end

function fig = plotAmSpectra(baseband, modulated, demodulated, fs, metrics)
[fb, mb] = spectrumDb(baseband, fs);
[fm, mm] = spectrumDb(modulated, fs);
[fd, md] = spectrumDb(demodulated, fs);
fig = figure('Visible', 'off', 'Color', 'w', 'Name', 'AM 频谱搬移与低通恢复结果', 'Position', [100 100 1100 780]);
tiledlayout(fig, 3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
plot(fb, mb, 'Color', [0.10 0.32 0.65], 'LineWidth', 1.0);
grid on; xlabel('Frequency / Hz'); ylabel('Magnitude / dB'); title('基带频谱');
xlim([0 1800]); ylim([-110 5]);
nexttile;
plot(fm / 1000, mm, 'Color', [0.76 0.28 0.14], 'LineWidth', 1.0);
grid on; xlabel('Frequency / kHz'); ylabel('Magnitude / dB'); title('AM 调制后频谱（载波及边带）');
xlim([0 fs/2000]); ylim([-110 5]);
hold on; drawVerticalMarkerLocal(4.0, 'fc');
nexttile;
plot(fd, md, 'Color', [0.18 0.55 0.28], 'LineWidth', 1.0);
grid on; xlabel('Frequency / Hz'); ylabel('Magnitude / dB');
title(sprintf('解调低通恢复频谱（corr=%.3f, SNR=%.2f dB, NMSE=%.4g）', ...
    metrics.correlation, metrics.reconstructionSnrDb, metrics.nmse));
xlim([0 1800]); ylim([-110 5]);
end

function drawVerticalMarkerLocal(xValue, labelText)
yLimits = ylim;
line([xValue xValue], yLimits, 'Color', [0.1 0.1 0.1], 'LineStyle', '--', 'LineWidth', 0.8);
text(xValue, yLimits(2) - 8, labelText, 'Rotation', 90, 'VerticalAlignment', 'top', 'HorizontalAlignment', 'right');
end

function yPlot = matchRmsForPlot(y, reference)
yPlot = y(:);
refRms = sqrt(mean(reference(:).^2));
yRms = sqrt(mean(yPlot.^2));
if refRms > eps && yRms > eps
    yPlot = yPlot * (refRms / yRms);
end
end

function [f, magDb] = spectrumDb(x, fs)
x = double(x(:));
x(~isfinite(x)) = 0;
if isempty(x)
    f = 0;
    magDb = -120;
    return;
end
n = numel(x);
nfft = 2 ^ nextpow2(max(n, 2048));
window = hannLocal(n);
X = fft(x .* window, nfft);
half = 1:floor(nfft/2)+1;
mag = abs(X(half)) / max(sum(window), eps);
magDb = 20 * log10(mag / max(max(mag), eps) + 1e-12);
f = (half(:)-1) * fs / nfft;
end

function plotLocalSpectrogram(x, fs)
x = double(x(:));
winLength = min(max(256, round(0.035 * fs)), max(256, numel(x)));
hop = max(1, round(winLength * 0.35));
nfft = 2 ^ nextpow2(max(winLength, 512));
window = hannLocal(winLength);
numFrames = max(1, 1 + floor((numel(x) - winLength) / hop));
if numel(x) < winLength
    x(end+1:winLength,1) = 0;
    numFrames = 1;
end
powerDb = zeros(floor(nfft/2)+1, numFrames);
for k = 1:numFrames
    startIndex = (k-1) * hop + 1;
    frame = x(startIndex:startIndex+winLength-1) .* window;
    X = fft(frame, nfft);
    p = abs(X(1:floor(nfft/2)+1)).^2;
    powerDb(:, k) = 10 * log10(p / max(max(p), eps) + 1e-12);
end
t = ((0:numFrames-1) * hop + winLength/2) / fs;
f = (0:floor(nfft/2)) * fs / nfft / 1000;
imagesc(t, f, powerDb);
axis xy;
colormap(parula);
colorbar;
xlabel('Time / s');
ylabel('Frequency / kHz');
ylim([0 min(8, fs/2000)]);
caxis([-90 0]);
end

function saveFigure(fig, pathName)
set(fig, 'Color', 'w');
cleanupFigureText(fig);
drawnow;
exportgraphics(fig, pathName, 'Resolution', 300);
close(fig);
end

function cleanupFigureText(fig)
global REPORT_FIGURE_BOX_GLYPH_DETECTED REPORT_FIGURE_FONT
fontObjects = findall(fig, '-property', 'FontName');
for k = 1:numel(fontObjects)
    try
        set(fontObjects(k), 'FontName', REPORT_FIGURE_FONT);
    catch
    end
end
interpreterObjects = findall(fig, '-property', 'Interpreter');
for k = 1:numel(interpreterObjects)
    try
        set(interpreterObjects(k), 'Interpreter', 'none');
    catch
    end
end
textObjects = findall(fig, '-property', 'String');
for k = 1:numel(textObjects)
    try
        currentText = get(textObjects(k), 'String');
        cleanedText = cleanFigureString(currentText);
        set(textObjects(k), 'String', cleanedText);
        if stringHasBoxGlyph(cleanedText)
            REPORT_FIGURE_BOX_GLYPH_DETECTED = true;
        end
    catch
    end
end
end

function out = cleanFigureString(value)
if iscell(value)
    out = value;
    for k = 1:numel(value)
        out{k} = cleanFigureString(value{k});
    end
    return;
end
if isstring(value)
    out = value;
    for k = 1:numel(value)
        out(k) = string(cleanFigureString(char(value(k))));
    end
    return;
end
if ~ischar(value)
    out = value;
    return;
end
text = value;
replacements = {
    '公开合成语音波形概览', 'Public synthetic speech waveform overview'
    '原始音频与预处理结果对比', 'Original vs preprocessed audio'
    '原始合成语音样本二', 'Original synthetic speech alternate'
    '原始合成语音样本', 'Original synthetic speech sample'
    '预处理后合成语音样本', 'Preprocessed synthetic speech sample'
    '原始预处理', 'Preprocessed original'
    '三类典型噪声添加结果', 'Three typical noise examples'
    '白噪声', 'White noise'
    '工频噪声', 'Mains hum noise'
    '脉冲噪声', 'Impulse noise'
    '加 50 Hz 工频噪声后', 'After 50 Hz hum noise'
    '滤波去噪前后对比', 'Filtering before and after'
    '不同滤波器幅频响应对比', 'Filter response comparison'
    '五类滤波器幅频响应', 'Five filter magnitude responses'
    '低频与语音频带细节', 'Low-frequency and voice-band detail'
    '电话音音效处理结果', 'Telephone effect result'
    '广播音音效处理结果', 'Radio effect result'
    'Bitcrusher 音效处理结果', 'Bitcrusher effect result'
    '留声机音效处理结果', 'Gramophone effect result'
    '机器人音效处理结果', 'Robot effect result'
    'Lo-Fi 音效处理结果', 'Lo-Fi effect result'
    '处理后', 'Processed'
    'Delay 空间效果处理结果', 'Delay space effect result'
    'Bathroom 空间效果处理结果', 'Bathroom space effect result'
    'Cave 空间效果处理结果', 'Cave space effect result'
    '空间效果', 'Space effect'
    'AM 调制解调波形恢复结果', 'AM modulation-demodulation waveform recovery'
    'AM 调制解调频谱搬移与低通恢复结果', 'AM spectrum shift and low-pass recovery'
    '基带信号', 'Baseband signal'
    '独白片段', 'monologue segment'
    '低频测试基带', 'low-frequency test baseband'
    'AM 调制信号', 'AM modulated signal'
    '解调恢复信号', 'Demodulated recovery signal'
    '基带频谱', 'Baseband spectrum'
    'AM 调制后频谱', 'AM modulated spectrum'
    '载波及边带', 'carrier and sidebands'
    '解调低通恢复频谱', 'Demodulated low-pass recovery spectrum'
    '波形对比', 'Waveform comparison'
    '频谱对比', 'Spectrum comparison'
    '声谱图', 'Spectrogram'
};
for k = 1:size(replacements, 1)
    text = strrep(text, replacements{k, 1}, replacements{k, 2});
end
text = strrep(text, char(8216), '''');
text = strrep(text, char(8217), '''');
text = strrep(text, char(8220), '"');
text = strrep(text, char(8221), '"');
text = strrep(text, char(8211), '-');
text = strrep(text, char(8212), '-');
text = strrep(text, char(65288), '(');
text = strrep(text, char(65289), ')');
text = strrep(text, char(65306), ':');
text = regexprep(text, '[^\x20-\x7E]', ' ');
text = regexprep(text, '\s+', ' ');
text = strtrim(text);
if isempty(text)
    text = 'Result comparison';
end
out = text;
end

function tf = stringHasBoxGlyph(value)
tf = false;
if iscell(value)
    for k = 1:numel(value)
        tf = tf || stringHasBoxGlyph(value{k});
    end
    return;
end
if isstring(value)
    value = char(join(value, ' '));
end
if ischar(value)
    tf = contains(value, char(9633)) || contains(value, char(9744));
end
end

function rows = appendManifestRow(rows, filename, captionCn, sampleFile, moduleName, modeName, sectionName, wavFile, priority, notes)
rows(end+1, :) = {filename, captionCn, sampleFile, moduleName, modeName, sectionName, wavFile, priority, notes};
end

function rows = appendFailureRow(rows, filename, captionCn, moduleName, modeName, sectionName, err)
rows = appendManifestRow(rows, filename, captionCn, '', moduleName, modeName, sectionName, '', ...
    'C_备用', ['导出失败或跳过: ', compactError(err)]);
end

function writeManifestCsv(pathName, rows)
headers = {'filename','caption_cn','sample_file','module','mode','recommended_report_section','wav_file','priority','notes'};
fid = fopen(pathName, 'w', 'n', 'UTF-8');
if fid < 0
    error('exportReportFigures:ManifestOpenFailed', 'Cannot write manifest: %s', pathName);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, [239 187 191], 'uint8');
writeCsvLine(fid, headers);
for k = 1:size(rows, 1)
    writeCsvLine(fid, rows(k, :));
end
end

function writeCsvLine(fid, values)
for k = 1:numel(values)
    if k > 1
        fprintf(fid, ',');
    end
    fprintf(fid, '%s', csvEscape(values{k}));
end
fprintf(fid, '\n');
end

function out = csvEscape(value)
if isnumeric(value)
    value = num2str(value);
elseif isstring(value)
    value = char(value);
elseif ~ischar(value)
    value = char(string(value));
end
value = strrep(value, '"', '""');
out = ['"', value, '"'];
end

function writeManualScreenshotReadme(pathName, manualNames)
fid = fopen(pathName, 'w', 'n', 'UTF-8');
if fid < 0
    error('exportReportFigures:ManualReadmeOpenFailed', 'Cannot write %s.', pathName);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '以下 App 截图需要人工补充，建议保存到本文件夹：\n\n');
for k = 1:numel(manualNames)
    fprintf(fid, '%d. %s\n', k, manualNames{k});
end
fprintf(fid, '5. AM Lab 截图无法自动生成，已用脚本导出的 AM 波形/频谱图替代。\n');
fprintf(fid, '\n说明：当前项目入口为 app/launchVoiceFXApp.m，主界面为 app/VoiceFXApp.m；当前项目没有独立 AM Lab 页面。\n');
end

function writeRunReadme(pathName, runStarted, outputRoot, matlabVersion, sampleFiles, ...
    pngCount, wavCount, voiceSinglePngCount, voiceOverviewPngCount, ...
    voiceWavCount, fontName, figureTextMode, boxGlyphDetected, failures, skipped)
fid = fopen(pathName, 'w', 'n', 'UTF-8');
if fid < 0
    error('exportReportFigures:ReadmeOpenFailed', 'Cannot write %s.', pathName);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'VoiceFX 实验报告专用结果图导出说明\n\n');
fprintf(fid, '运行时间: %s\n', char(runStarted));
fprintf(fid, 'MATLAB 版本: %s\n', matlabVersion);
fprintf(fid, '输出目录: %s\n', outputRoot);
fprintf(fid, '成功导出 PNG 总数: %d\n', pngCount);
fprintf(fid, '成功导出 WAV 总数: %d\n\n', wavCount);
fprintf(fid, '本次是在旧报告导图基础上的补充修正。\n');
fprintf(fid, '新增了 2 个合成语音样本 x 4 个自适应声线模式的 8 张单图。实际成功: %d/8。\n', voiceSinglePngCount);
fprintf(fid, '新增了 4 张同一声线模式跨 2 个合成语音样本横向比较总览图。实际成功: %d/4。\n', voiceOverviewPngCount);
fprintf(fid, '新增处理后 WAV: %d/8。\n', voiceWavCount);
fprintf(fid, '已尝试修复 MATLAB 图中文字方框问题，优先字体: %s。\n', fontName);
fprintf(fid, '最终图内文字采用: %s。文件名和 figure_manifest.csv 的中文图注保留中文。\n', figureTextMode);
if boxGlyphDetected
    fprintf(fid, '方框乱码检测结果: Box-glyph issue detected in figure text properties.\n\n');
else
    fprintf(fid, '方框乱码检测结果: No box-glyph issue detected.\n\n');
end
fprintf(fid, '使用样本文件:\n');
if isempty(sampleFiles)
    fprintf(fid, '- 无可用样本。\n');
else
    for k = 1:numel(sampleFiles)
        fprintf(fid, '- %s\n', sampleFiles{k});
    end
end
fprintf(fid, '\n失败或跳过项目:\n');
if isempty(failures) && isempty(skipped)
    fprintf(fid, '- 无\n');
else
    for k = 1:numel(failures)
        fprintf(fid, '- %s\n', failures{k});
    end
    for k = 1:numel(skipped)
        fprintf(fid, '- %s\n', skipped{k});
    end
end
fprintf(fid, '\n请查看 figure_manifest.csv 选择插图优先级，并查看 screenshots_manual/README_需要人工截图.txt 补充人工截图。\n');
end

function color = reportColor(index)
palette = [
    0.10 0.32 0.65
    0.76 0.28 0.14
    0.18 0.55 0.28
    0.50 0.30 0.62
    0.35 0.35 0.35
    0.85 0.55 0.10
];
color = palette(mod(index-1, size(palette, 1)) + 1, :);
end

function limits = axisLimitForSignals(x)
peak = max(abs(x(:)));
peak = max(peak, 0.05);
limits = [-1 1] * min(1.05, 1.15 * peak);
end

function w = hannLocal(n)
n = max(1, round(n));
if n <= 1
    w = ones(n, 1);
else
    idx = (0:n-1).';
    w = 0.5 - 0.5 * cos(2*pi*idx/(n-1));
end
end

function w = tukeyWindowLocal(n, ratio)
if n <= 1
    w = ones(n, 1);
    return;
end
ratio = min(max(double(ratio), 0), 1);
if ratio <= 0
    w = ones(n, 1);
    return;
end
w = ones(n, 1);
edge = floor(ratio * (n - 1) / 2);
if edge <= 0
    return;
end
idx = (0:edge).';
taper = 0.5 * (1 + cos(pi * (2 * idx / (ratio * (n - 1)) - 1)));
w(1:edge+1) = taper;
w(end-edge:end) = flipud(taper);
end

function y = resampleLinearLocal(x, fsIn, fsOut)
x = double(x(:));
if fsIn == fsOut || isempty(x)
    y = x;
    return;
end
duration = (numel(x) - 1) / fsIn;
tIn = (0:numel(x)-1).' / fsIn;
tOut = (0:1/fsOut:duration).';
y = interp1(tIn, x, tOut, 'linear', 'extrap');
end

function statusText = logicalStatus(value)
if value
    statusText = 'yes';
else
    statusText = 'no';
end
end

function text = compactError(err)
text = err.message;
text = strrep(text, newline, ' ');
text = regexprep(text, '\s+', ' ');
end

