classdef VoiceFXApp < handle
    %VOICEFXAPP Programmatic UI for the VoiceFX file-mode audio workstation.

    properties
        RootDir char
        InputPath char = ''
        Fs double = []
        XOriginal double = []
        XProcessedInput double = []
        YProcessed double = []
        Player = []
        LastResult = []
        CurrentConfig = []
    end

    properties (Access = private)
        UIFigure
        FileNameLabel
        FileInfoLabel
        SampleDropDown
        PresetDropDown
        NoiseDropDown
        FilterDropDown
        VoiceDropDown
        FxDropDown
        SpaceDropDown
        AmDropDown
        LiveInputDropDown
        LiveOutputDropDown
        LiveVoiceDropDown
        RefreshLiveDevicesButton
        StartLiveButton
        StopLiveButton
        ProcessButton
        PlayOriginalButton
        PlayProcessedButton
        StopButton
        SaveButton
        StatusArea
        WaveInAxes
        WaveOutAxes
        SpectrumInAxes
        SpectrumOutAxes
        SpectrogramAxes
        ChainArea
        LiveStatusArea
        LiveStopRequested logical = false
    end

    methods
        function app = VoiceFXApp(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = VoiceFXApp.locateProjectRoot();
            end
            app.RootDir = char(projectRoot);
            app.addProjectPaths();
            app.CurrentConfig = makeAppConfig();
            app.buildUI();
            app.refreshSampleList();
            app.refreshLiveDevices(false);
            app.updateButtonState();
            app.appendStatus('App 已启动。请先导入音频或选择 samples 示例。');
        end

        function delete(app)
            app.stopPlayback();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function addProjectPaths(app)
            addpath(fullfile(app.RootDir, 'core'));
            addpath(fullfile(app.RootDir, 'modules'));
            addpath(fullfile(app.RootDir, 'app'));
            realtimeDir = fullfile(app.RootDir, 'realtime');
            if exist(realtimeDir, 'dir') == 7
                addpath(realtimeDir);
            end
        end

        function buildUI(app)
            bg = [0.94 0.95 0.97];
            surface = [1.00 1.00 1.00];
            softSurface = [0.97 0.98 0.99];
            textMain = [0.10 0.12 0.16];
            muted = [0.42 0.46 0.52];
            accent = [0.12 0.36 0.82];
            accentSoft = [0.09 0.50 0.38];

            app.UIFigure = uifigure('Name', 'VoiceFX 信号与系统语音处理 App', ...
                'Position', [35 35 1500 940], 'Color', bg);
            app.UIFigure.CloseRequestFcn = @(~, ~) app.onClose();

            root = uigridlayout(app.UIFigure, [2 2]);
            root.RowHeight = {66, '1x'};
            root.ColumnWidth = {450, '1x'};
            root.Padding = [20 16 20 18];
            root.RowSpacing = 10;
            root.ColumnSpacing = 16;
            root.BackgroundColor = bg;

            header = uipanel(root, 'BorderType', 'none', 'BackgroundColor', bg);
            header.Layout.Row = 1;
            header.Layout.Column = [1 2];
            headerGrid = uigridlayout(header, [2 1]);
            headerGrid.RowHeight = {34, 22};
            headerGrid.Padding = [2 4 2 0];
            headerGrid.RowSpacing = 2;
            headerGrid.BackgroundColor = bg;
            titleLabel = uilabel(headerGrid, 'Text', 'VoiceFX 信号与系统语音处理 App', ...
                'FontSize', 24, 'FontWeight', 'bold', 'FontColor', textMain);
            titleLabel.Layout.Row = 1;
            subLabel = uilabel(headerGrid, 'Text', '文件处理 | 声线风格 | 音效 | 空间效果 | 时频域分析', ...
                'FontSize', 13, 'FontColor', muted);
            subLabel.Layout.Row = 2;

            left = uipanel(root, 'BorderType', 'none', 'BackgroundColor', bg);
            left.Layout.Row = 2;
            left.Layout.Column = 1;
            leftGrid = uigridlayout(left, [5 1]);
            leftGrid.RowHeight = {170, 76, 310, 168, '1x'};
            leftGrid.Padding = [0 0 0 0];
            leftGrid.RowSpacing = 8;
            leftGrid.BackgroundColor = bg;

            filePanel = app.makeSection(leftGrid, '音频文件');
            filePanel.Layout.Row = 1;
            fileGrid = uigridlayout(filePanel, [5 1]);
            fileGrid.RowHeight = {32, 30, 27, 27, 22};
            fileGrid.Padding = [14 10 14 10];
            fileGrid.RowSpacing = 6;
            fileGrid.BackgroundColor = surface;
            chooseButton = uibutton(fileGrid, 'push', 'Text', '选择音频', ...
                'ButtonPushedFcn', @(~, ~) app.onChooseFile(), 'FontWeight', 'bold');
            chooseButton.BackgroundColor = accent;
            chooseButton.FontColor = [1 1 1];
            app.SampleDropDown = uidropdown(fileGrid, 'Items', {'选择 samples 示例'}, ...
                'ValueChangedFcn', @(~, ~) app.onSampleSelected());
            app.FileNameLabel = uilabel(fileGrid, 'Text', '当前文件：未选择', 'FontColor', textMain, 'FontSize', 13);
            app.FileNameLabel.WordWrap = 'on';
            app.FileInfoLabel = uilabel(fileGrid, 'Text', '采样率：-    时长：-', 'FontColor', muted, 'FontSize', 13);
            app.FileInfoLabel.WordWrap = 'on';
            hint = uilabel(fileGrid, 'Text', '导入 -> 选择处理链 -> 处理 -> 播放/保存', 'FontColor', muted, 'FontSize', 12);
            hint.WordWrap = 'on';

            presetPanel = app.makeSection(leftGrid, '推荐预设');
            presetPanel.Layout.Row = 2;
            presetGrid = uigridlayout(presetPanel, [1 1]);
            presetGrid.Padding = [14 10 14 10];
            presetGrid.BackgroundColor = surface;
            app.PresetDropDown = uidropdown(presetGrid, ...
                'Items', {'手动选择', '原声清理', '深沉男声 + 电话音', '柔和女声 + Lo-fi', ...
                '明亮童声 + 浴室混响', '稳定老年声 + 留声机', '深沉男声 + 山洞空间', ...
                'Robot 音效 + Bitcrusher'}, ...
                'ItemsData', {'manual', 'clean', 'male_phone', 'female_lofi', ...
                'child_bathroom', 'elder_gramophone', 'male_cave', 'robot_bitcrusher'}, ...
                'Value', 'manual', 'ValueChangedFcn', @(~, ~) app.onPresetChanged());
            app.PresetDropDown.FontSize = 13;

            chainPanel = app.makeSection(leftGrid, '处理链');
            chainPanel.Layout.Row = 3;
            chainGrid = uigridlayout(chainPanel, [6 2]);
            chainGrid.RowHeight = repmat({36}, 1, 6);
            chainGrid.ColumnWidth = {82, '1x'};
            chainGrid.Padding = [14 12 14 12];
            chainGrid.RowSpacing = 7;
            chainGrid.ColumnSpacing = 8;
            chainGrid.BackgroundColor = surface;
            app.NoiseDropDown = app.addDropdownRow(chainGrid, 1, '噪声', {'none', 'white', 'hum50', 'impulse'}, {'none', 'white', 'hum50', 'impulse'});
            app.FilterDropDown = app.addDropdownRow(chainGrid, 2, '滤波', {'none', 'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'}, {'none', 'highpass', 'lowpass', 'bandpass', 'notch50', 'voice_enhance'});
            app.VoiceDropDown = app.addDropdownRow(chainGrid, 3, '声线', ...
                {'none', 'male_deep_gentle', 'female_gentle_sweet', 'child_bright_soft', ...
                'elder_warm_steady'}, ...
                {'none', 'male_deep_gentle', 'female_gentle_sweet', 'child_bright_soft', ...
                'elder_warm_steady'});
            app.FxDropDown = app.addDropdownRow(chainGrid, 4, '音效', {'none', 'telephone', 'radio', 'lofi', 'bitcrusher', 'gramophone', 'robot'}, {'none', 'telephone', 'radio', 'lofi', 'bitcrusher', 'gramophone', 'robot'});
            app.SpaceDropDown = app.addDropdownRow(chainGrid, 5, '空间', {'none', 'delay', 'bathroom', 'cave'}, {'none', 'delay', 'bathroom', 'cave'});
            app.AmDropDown = app.addDropdownRow(chainGrid, 6, 'AM', {'off', 'modulate', 'demodulate'}, {'off', 'modulate', 'demodulate'});

            opsPanel = app.makeSection(leftGrid, '播放与导出');
            opsPanel.Layout.Row = 4;
            opsGrid = uigridlayout(opsPanel, [3 2]);
            opsGrid.RowHeight = {38, 34, 34};
            opsGrid.ColumnWidth = {'1x', '1x'};
            opsGrid.Padding = [14 12 14 12];
            opsGrid.RowSpacing = 9;
            opsGrid.ColumnSpacing = 8;
            opsGrid.BackgroundColor = surface;
            app.ProcessButton = uibutton(opsGrid, 'push', 'Text', '处理音频', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.onProcessAudio());
            app.ProcessButton.Layout.Row = 1;
            app.ProcessButton.Layout.Column = [1 2];
            app.ProcessButton.BackgroundColor = accentSoft;
            app.ProcessButton.FontColor = [1 1 1];
            app.PlayOriginalButton = uibutton(opsGrid, 'push', 'Text', '播放原音', 'ButtonPushedFcn', @(~, ~) app.onPlayOriginal());
            app.PlayOriginalButton.Layout.Row = 2;
            app.PlayOriginalButton.Layout.Column = 1;
            app.PlayOriginalButton.FontSize = 13;
            app.PlayProcessedButton = uibutton(opsGrid, 'push', 'Text', '播放处理后', 'ButtonPushedFcn', @(~, ~) app.onPlayProcessed());
            app.PlayProcessedButton.Layout.Row = 2;
            app.PlayProcessedButton.Layout.Column = 2;
            app.PlayProcessedButton.FontSize = 13;
            app.StopButton = uibutton(opsGrid, 'push', 'Text', '停止播放', 'ButtonPushedFcn', @(~, ~) app.onStopOrSave());
            app.StopButton.Layout.Row = 3;
            app.StopButton.Layout.Column = 1;
            app.StopButton.FontSize = 13;
            app.SaveButton = uibutton(opsGrid, 'push', 'Text', '保存结果', 'ButtonPushedFcn', @(~, ~) app.onSaveResult());
            app.SaveButton.Layout.Row = 3;
            app.SaveButton.Layout.Column = 2;
            app.SaveButton.FontSize = 13;

            logPanel = app.makeSection(leftGrid, '状态日志');
            logPanel.Layout.Row = 5;
            logGrid = uigridlayout(logPanel, [1 1]);
            logGrid.Padding = [14 10 14 10];
            logGrid.BackgroundColor = surface;
            app.StatusArea = uitextarea(logGrid, 'Editable', 'off', 'Value', {'等待操作。'});
            app.StatusArea.FontName = 'Microsoft YaHei UI';
            app.StatusArea.FontSize = 13;

            right = uipanel(root, 'BorderType', 'none', 'BackgroundColor', bg);
            right.Layout.Row = 2;
            right.Layout.Column = 2;
            rightGrid = uigridlayout(right, [1 1]);
            rightGrid.Padding = [0 0 0 0];
            rightGrid.BackgroundColor = bg;
            tabs = uitabgroup(rightGrid);
            tabs.Layout.Row = 1;
            tabs.Layout.Column = 1;

            waveTab = uitab(tabs, 'Title', '波形');
            waveGrid = uigridlayout(waveTab, [2 1]);
            waveGrid.RowHeight = {'1x', '1x'};
            waveGrid.Padding = [18 16 18 18];
            waveGrid.RowSpacing = 14;
            waveGrid.BackgroundColor = softSurface;
            app.WaveInAxes = uiaxes(waveGrid);
            app.WaveInAxes.Layout.Row = 1;
            app.WaveInAxes.Layout.Column = 1;
            app.WaveOutAxes = uiaxes(waveGrid);
            app.WaveOutAxes.Layout.Row = 2;
            app.WaveOutAxes.Layout.Column = 1;
            app.styleAxes(app.WaveInAxes, '原始 / 预处理输入波形', '时间 (s)', '幅度');
            app.styleAxes(app.WaveOutAxes, '处理后波形', '时间 (s)', '幅度');

            specTab = uitab(tabs, 'Title', '频谱');
            specGrid = uigridlayout(specTab, [2 1]);
            specGrid.RowHeight = {'1x', '1x'};
            specGrid.Padding = [18 16 18 18];
            specGrid.RowSpacing = 14;
            specGrid.BackgroundColor = softSurface;
            app.SpectrumInAxes = uiaxes(specGrid);
            app.SpectrumInAxes.Layout.Row = 1;
            app.SpectrumInAxes.Layout.Column = 1;
            app.SpectrumOutAxes = uiaxes(specGrid);
            app.SpectrumOutAxes.Layout.Row = 2;
            app.SpectrumOutAxes.Layout.Column = 1;
            app.styleAxes(app.SpectrumInAxes, '原始频谱', '频率 (Hz)', '幅度 (dB)');
            app.styleAxes(app.SpectrumOutAxes, '处理后频谱', '频率 (Hz)', '幅度 (dB)');

            sgTab = uitab(tabs, 'Title', '声谱图');
            sgGrid = uigridlayout(sgTab, [1 1]);
            sgGrid.Padding = [18 16 18 18];
            sgGrid.BackgroundColor = softSurface;
            app.SpectrogramAxes = uiaxes(sgGrid);
            app.SpectrogramAxes.Layout.Row = 1;
            app.SpectrogramAxes.Layout.Column = 1;
            app.styleAxes(app.SpectrogramAxes, '处理后声谱图', '时间 (s)', '频率 (Hz)');

            chainTab = uitab(tabs, 'Title', '处理链说明');
            chainGrid2 = uigridlayout(chainTab, [1 1]);
            chainGrid2.RowHeight = {'1x'};
            chainGrid2.Padding = [18 16 18 18];
            chainGrid2.BackgroundColor = softSurface;
            app.ChainArea = uitextarea(chainGrid2, 'Editable', 'off', 'FontName', 'Microsoft YaHei UI');
            app.ChainArea.Layout.Row = 1;
            app.ChainArea.FontSize = 14;

            liveTab = uitab(tabs, 'Title', '实时模式 / Live');
            liveGrid = uigridlayout(liveTab, [7 2]);
            liveGrid.RowHeight = {36, 36, 36, 38, 38, '1x', 88};
            liveGrid.ColumnWidth = {130, '1x'};
            liveGrid.Padding = [18 16 18 18];
            liveGrid.RowSpacing = 10;
            liveGrid.ColumnSpacing = 10;
            liveGrid.BackgroundColor = softSurface;

            inputLabel = uilabel(liveGrid, 'Text', '输入设备', 'FontColor', textMain, 'FontSize', 13);
            inputLabel.Layout.Row = 1;
            inputLabel.Layout.Column = 1;
            app.LiveInputDropDown = uidropdown(liveGrid, 'Items', {'默认设备'}, 'ItemsData', {''});
            app.LiveInputDropDown.Layout.Row = 1;
            app.LiveInputDropDown.Layout.Column = 2;

            outputLabel = uilabel(liveGrid, 'Text', '输出设备', 'FontColor', textMain, 'FontSize', 13);
            outputLabel.Layout.Row = 2;
            outputLabel.Layout.Column = 1;
            app.LiveOutputDropDown = uidropdown(liveGrid, 'Items', {'默认设备'}, 'ItemsData', {''});
            app.LiveOutputDropDown.Layout.Row = 2;
            app.LiveOutputDropDown.Layout.Column = 2;

            voiceLabel = uilabel(liveGrid, 'Text', '实时声线', 'FontColor', textMain, 'FontSize', 13);
            voiceLabel.Layout.Row = 3;
            voiceLabel.Layout.Column = 1;
            liveVoiceModes = {'none', 'male_deep_gentle', 'female_gentle_sweet', 'child_bright_soft', 'elder_warm_steady'};
            app.LiveVoiceDropDown = uidropdown(liveGrid, 'Items', liveVoiceModes, 'ItemsData', liveVoiceModes, 'Value', 'none');
            app.LiveVoiceDropDown.Layout.Row = 3;
            app.LiveVoiceDropDown.Layout.Column = 2;

            app.RefreshLiveDevicesButton = uibutton(liveGrid, 'push', 'Text', '刷新设备', ...
                'ButtonPushedFcn', @(~, ~) app.onRefreshLiveDevices());
            app.RefreshLiveDevicesButton.Layout.Row = 4;
            app.RefreshLiveDevicesButton.Layout.Column = [1 2];

            app.StartLiveButton = uibutton(liveGrid, 'push', 'Text', '开始实时', ...
                'ButtonPushedFcn', @(~, ~) app.onStartLive());
            app.StartLiveButton.Layout.Row = 5;
            app.StartLiveButton.Layout.Column = 1;
            app.StartLiveButton.BackgroundColor = accentSoft;
            app.StartLiveButton.FontColor = [1 1 1];
            app.StopLiveButton = uibutton(liveGrid, 'push', 'Text', '停止实时', ...
                'ButtonPushedFcn', @(~, ~) app.onStopLive());
            app.StopLiveButton.Layout.Row = 5;
            app.StopLiveButton.Layout.Column = 2;

            instructionArea = uitextarea(liveGrid, 'Editable', 'off', 'FontName', 'Microsoft YaHei UI');
            instructionArea.Layout.Row = 6;
            instructionArea.Layout.Column = [1 2];
            instructionArea.FontSize = 13;
            instructionArea.Value = {'Live entry: refresh devices and copy the command-line runner command.', ...
                'The App does not start the realtime loop inside a UI callback, so file mode stays responsive.', ...
                'Run realtime/runRealtimeVoiceChanger.m in MATLAB Command Window and press Ctrl+C to stop.'};

            app.LiveStatusArea = uitextarea(liveGrid, 'Editable', 'off', 'FontName', 'Microsoft YaHei UI');
            app.LiveStatusArea.Layout.Row = 7;
            app.LiveStatusArea.Layout.Column = [1 2];
            app.LiveStatusArea.FontSize = 13;
            app.LiveStatusArea.Value = {'Live status: waiting for device refresh.'};

            app.updateChainDescription();
        end
        function panel = makeSection(~, parent, titleText)
            panel = uipanel(parent, 'Title', titleText, 'FontWeight', 'bold', ...
                'ForegroundColor', [0.18 0.20 0.24], 'BackgroundColor', [1 1 1], ...
                'BorderType', 'line');
            panel.FontSize = 14;
        end

        function dd = addDropdownRow(app, parent, row, labelText, items, data)
            lbl = uilabel(parent, 'Text', labelText, 'FontColor', [0.24 0.27 0.32], 'FontSize', 13);
            lbl.Layout.Row = row;
            lbl.Layout.Column = 1;
            dd = uidropdown(parent, 'Items', items, 'ItemsData', data, 'Value', data{1}, ...
                'ValueChangedFcn', @(~, ~) app.onChainChanged());
            dd.Layout.Row = row;
            dd.Layout.Column = 2;
            dd.FontSize = 13;
        end

        function styleAxes(~, ax, titleText, xText, yText)
            title(ax, titleText, 'FontWeight', 'bold');
            xlabel(ax, xText);
            ylabel(ax, yText);
            grid(ax, 'on');
            ax.Color = [1.00 1.00 1.00];
            ax.XColor = [0.25 0.28 0.34];
            ax.YColor = [0.25 0.28 0.34];
            ax.GridColor = [0.82 0.85 0.90];
            ax.FontName = 'Microsoft YaHei UI';
            ax.FontSize = 12;
            box(ax, 'on');
        end

        function refreshSampleList(app)
            sampleDir = fullfile(app.RootDir, 'samples');
            files = dir(fullfile(sampleDir, '*.wav'));
            if isempty(files)
                app.SampleDropDown.Items = {'samples 中没有 wav'};
                app.SampleDropDown.ItemsData = {''};
                app.SampleDropDown.Value = '';
                return;
            end
            names = [{ '选择 samples 示例' }, { files.name }];
            paths = cell(1, numel(names));
            paths{1} = '';
            for k = 1:numel(files)
                paths{k + 1} = fullfile(files(k).folder, files(k).name);
            end
            app.SampleDropDown.Items = names;
            app.SampleDropDown.ItemsData = paths;
            app.SampleDropDown.Value = '';
        end

        function onChooseFile(app)
            [fileName, folder] = uigetfile({'*.wav;*.flac;*.mp3;*.m4a', '音频文件 (*.wav, *.flac, *.mp3, *.m4a)'; '*.*', '所有文件'}, ...
                '选择音频文件', fullfile(app.RootDir, 'samples'));
            if isequal(fileName, 0)
                app.appendStatus('已取消选择音频。');
                return;
            end
            app.loadAudio(fullfile(folder, fileName));
        end

        function onSampleSelected(app)
            value = app.SampleDropDown.Value;
            if isempty(value)
                return;
            end
            app.loadAudio(value);
        end

        function loadAudio(app, pathName)
            try
                [x, fs] = audioread(pathName);
                cfg = makeAppConfig(app.currentSelections());
                app.InputPath = char(pathName);
                app.Fs = fs;
                app.XOriginal = preprocessAudio(x, fs, cfg);
                app.XProcessedInput = [];
                app.YProcessed = [];
                app.LastResult = [];
                app.CurrentConfig = cfg;
                [~, name, ext] = fileparts(pathName);
                app.FileNameLabel.Text = ['当前文件：', name, ext];
                app.FileInfoLabel.Text = sprintf('采样率：%.0f Hz    时长：%.2f s', fs, numel(app.XOriginal) / fs);
                app.appendStatus(['已导入：', name, ext]);
                app.updatePlots();
                app.updateChainDescription();
                app.updateButtonState();
            catch ME
                app.appendStatus(['导入失败：', ME.message]);
                uialert(app.UIFigure, ME.message, '导入失败');
            end
        end

        function onPresetChanged(app)
            preset = app.PresetDropDown.Value;
            switch preset
                case 'clean'
                    app.setChain('none', 'voice_enhance', 'none', 'none', 'none', 'off');
                case 'male_phone'
                    app.setChain('none', 'voice_enhance', 'male_deep_gentle', 'telephone', 'none', 'off');
                case 'female_lofi'
                    app.setChain('none', 'voice_enhance', 'female_gentle_sweet', 'lofi', 'none', 'off');
                case 'child_bathroom'
                    app.setChain('none', 'voice_enhance', 'child_bright_soft', 'none', 'bathroom', 'off');
                case 'elder_gramophone'
                    app.setChain('none', 'bandpass', 'elder_warm_steady', 'gramophone', 'none', 'off');
                case 'male_cave'
                    app.setChain('none', 'voice_enhance', 'male_deep_gentle', 'none', 'cave', 'off');
                case 'robot_bitcrusher'
                    app.setChain('none', 'none', 'none', 'robot', 'none', 'off');
                otherwise
                    % Manual mode leaves current controls unchanged.
            end
            app.appendStatus(['预设已切换：', app.currentPresetName()]);
            app.onChainChanged();
        end

        function setChain(app, noiseMode, filterMode, voiceMode, fxMode, spaceMode, amMode)
            app.NoiseDropDown.Value = noiseMode;
            app.FilterDropDown.Value = filterMode;
            app.VoiceDropDown.Value = voiceMode;
            app.FxDropDown.Value = fxMode;
            app.SpaceDropDown.Value = spaceMode;
            app.AmDropDown.Value = amMode;
        end

        function onChainChanged(app)
            app.CurrentConfig = makeAppConfig(app.currentSelections());
            app.updateChainDescription();
        end

        function selections = currentSelections(app)
            selections = struct();
            selections.noise = app.NoiseDropDown.Value;
            selections.filter = app.FilterDropDown.Value;
            selections.voice = app.VoiceDropDown.Value;
            selections.fx = app.FxDropDown.Value;
            selections.space = app.SpaceDropDown.Value;
            selections.am = app.AmDropDown.Value;
        end

        function onRefreshLiveDevices(app)
            app.refreshLiveDevices(true);
        end

        function refreshLiveDevices(app, verboseStatus)
            if nargin < 2
                verboseStatus = true;
            end
            try
                devices = listAudioDevices(false);
                inputDevices = [{'默认设备'}, VoiceFXApp.normalizeDeviceItems(devices.input)];
                outputDevices = [{'默认设备'}, VoiceFXApp.normalizeDeviceItems(devices.output)];
                app.LiveInputDropDown.Items = inputDevices;
                app.LiveInputDropDown.ItemsData = [{''}, inputDevices(2:end)];
                app.LiveInputDropDown.Value = '';
                app.LiveOutputDropDown.Items = outputDevices;
                app.LiveOutputDropDown.ItemsData = [{''}, outputDevices(2:end)];
                app.LiveOutputDropDown.Value = '';
                if verboseStatus
                    app.appendLiveStatus(sprintf('Devices refreshed: %d input, %d output.', ...
                        numel(inputDevices) - 1, numel(outputDevices) - 1));
                end
            catch ME
                app.LiveInputDropDown.Items = {'默认设备'};
                app.LiveInputDropDown.ItemsData = {''};
                app.LiveInputDropDown.Value = '';
                app.LiveOutputDropDown.Items = {'默认设备'};
                app.LiveOutputDropDown.ItemsData = {''};
                app.LiveOutputDropDown.Value = '';
                app.appendLiveStatus(['Device refresh unavailable: ', ME.message]);
            end
        end

        function onStartLive(app)
            app.LiveStopRequested = false;
            commandText = app.makeRealtimeCommand();
            app.appendLiveStatus('Realtime loop was not started inside the App callback. Run this in MATLAB Command Window:');
            app.appendLiveStatus(commandText);
        end

        function onStopLive(app)
            app.LiveStopRequested = true;
            app.appendLiveStatus('Stop request recorded. If the realtime script is running in Command Window, press Ctrl+C.');
        end

        function commandText = makeRealtimeCommand(app)
            inputDevice = app.LiveInputDropDown.Value;
            outputDevice = app.LiveOutputDropDown.Value;
            voiceMode = app.LiveVoiceDropDown.Value;
            parts = {'options = struct()'};
            if ~isempty(inputDevice)
                parts{end + 1} = ['options.inputDevice = ''', VoiceFXApp.escapeMatlabString(inputDevice), '''']; %#ok<AGROW>
            end
            if ~isempty(outputDevice)
                parts{end + 1} = ['options.outputDevice = ''', VoiceFXApp.escapeMatlabString(outputDevice), '''']; %#ok<AGROW>
            end
            parts{end + 1} = 'options.enableSpeechClean = true'; %#ok<AGROW>
            parts{end + 1} = 'options.fxMode = ''none'''; %#ok<AGROW>
            parts{end + 1} = 'options.spaceMode = ''none'''; %#ok<AGROW>
            parts{end + 1} = ['runRealtimeVoiceChanger(Inf, ''', VoiceFXApp.escapeMatlabString(voiceMode), ''', options)']; %#ok<AGROW>
            commandText = strjoin(parts, '; ');
        end

        function onProcessAudio(app)
            if isempty(app.InputPath)
                app.appendStatus('请先导入音频。');
                return;
            end
            try
                app.ProcessButton.Enable = 'off';
                drawnow limitrate;
                cfg = makeAppConfig(app.currentSelections());
                app.CurrentConfig = cfg;
                app.appendStatus('开始处理音频...');
                result = runFileMode(app.InputPath, cfg);
                app.LastResult = result;
                app.Fs = result.fs;
                app.XOriginal = result.xOriginal;
                app.XProcessedInput = result.xProcessedInput;
                app.YProcessed = result.y;
                app.appendStatus(result.message);
                app.updatePlots();
                app.updateChainDescription();
            catch ME
                app.appendStatus(['处理失败：', ME.message]);
                uialert(app.UIFigure, ME.message, '处理失败');
            end
            app.ProcessButton.Enable = 'on';
            app.updateButtonState();
        end

        function onPlayOriginal(app)
            if isempty(app.XOriginal) || isempty(app.Fs)
                app.appendStatus('请先导入音频。');
                return;
            end
            app.playVector(app.XOriginal, app.Fs, '正在播放原音。');
        end

        function onPlayProcessed(app)
            if isempty(app.YProcessed) || isempty(app.Fs)
                app.appendStatus('请先处理音频，再播放处理后结果。');
                return;
            end
            app.playVector(app.YProcessed, app.Fs, '正在播放处理后结果。');
        end

        function onStopOrSave(app)
            if ~isempty(app.Player) && isplaying(app.Player)
                app.stopPlayback();
                app.appendStatus('播放已停止。');
            else
                app.appendStatus('当前没有正在播放的音频。');
            end
        end

        function onSaveResult(app)
            if isempty(app.YProcessed) || isempty(app.Fs)
                app.appendStatus('请先处理音频，再保存结果。');
                return;
            end
            [~, name] = fileparts(app.InputPath);
            defaultName = [name, '_VoiceFX.wav'];
            [fileName, folder] = uiputfile({'*.wav', 'WAV 音频 (*.wav)'}, '保存处理结果', fullfile(app.RootDir, 'results', defaultName));
            if isequal(fileName, 0)
                app.appendStatus('已取消保存。');
                return;
            end
            outputPath = fullfile(folder, fileName);
            if strcmpi(VoiceFXApp.canonicalPath(outputPath), VoiceFXApp.canonicalPath(app.InputPath))
                app.appendStatus('拒绝覆盖原始音频文件。请选择其他文件名。');
                uialert(app.UIFigure, '不能覆盖原始音频文件，请另存为新文件。', '保存被阻止');
                return;
            end
            try
                audiowrite(outputPath, app.YProcessed, app.Fs);
                app.appendStatus(['已保存：', outputPath]);
            catch ME
                app.appendStatus(['保存失败：', ME.message]);
                uialert(app.UIFigure, ME.message, '保存失败');
            end
        end

        function playVector(app, x, fs, message)
            try
                app.stopPlayback();
                x = double(x(:));
                x(~isfinite(x)) = 0;
                app.Player = audioplayer(x, fs);
                play(app.Player);
                app.appendStatus(message);
            catch ME
                app.appendStatus(['播放失败：', ME.message]);
                uialert(app.UIFigure, ME.message, '播放失败');
            end
        end

        function stopPlayback(app)
            try
                if ~isempty(app.Player)
                    stop(app.Player);
                end
            catch
            end
        end

        function updatePlots(app)
            app.plotWaveforms();
            app.plotSpectra();
            app.plotSpectrogram();
        end

        function plotWaveforms(app)
            cla(app.WaveInAxes);
            cla(app.WaveOutAxes);
            if isempty(app.XOriginal) || isempty(app.Fs)
                title(app.WaveInAxes, '原始 / 预处理输入波形');
                title(app.WaveOutAxes, '处理后波形');
                return;
            end
            inputForPlot = app.XOriginal;
            if ~isempty(app.XProcessedInput)
                inputForPlot = app.XProcessedInput;
            end
            [tIn, xIn] = VoiceFXApp.decimateForPlot(inputForPlot, app.Fs, 16000);
            plot(app.WaveInAxes, tIn, xIn, 'Color', [0.10 0.35 0.78], 'LineWidth', 1.0);
            app.styleAxes(app.WaveInAxes, '原始 / 预处理输入波形', '时间 (s)', '幅度');
            ylim(app.WaveInAxes, [-1.05 1.05]);

            if ~isempty(app.YProcessed)
                [tOut, yOut] = VoiceFXApp.decimateForPlot(app.YProcessed, app.Fs, 16000);
                plot(app.WaveOutAxes, tOut, yOut, 'Color', [0.08 0.55 0.36], 'LineWidth', 1.0);
            end
            app.styleAxes(app.WaveOutAxes, '处理后波形', '时间 (s)', '幅度');
            ylim(app.WaveOutAxes, [-1.05 1.05]);
        end

        function plotSpectra(app)
            cla(app.SpectrumInAxes);
            cla(app.SpectrumOutAxes);
            if isempty(app.XOriginal) || isempty(app.Fs)
                return;
            end
            [f, mag] = VoiceFXApp.makeSpectrum(app.XOriginal, app.Fs);
            plot(app.SpectrumInAxes, f, mag, 'Color', [0.10 0.35 0.78], 'LineWidth', 1.0);
            app.styleAxes(app.SpectrumInAxes, '原始频谱', '频率 (Hz)', '幅度 (dB)');
            xlim(app.SpectrumInAxes, [0 min(app.Fs / 2, 10000)]);
            ylim(app.SpectrumInAxes, [-100 5]);

            if ~isempty(app.YProcessed)
                [f2, mag2] = VoiceFXApp.makeSpectrum(app.YProcessed, app.Fs);
                plot(app.SpectrumOutAxes, f2, mag2, 'Color', [0.08 0.55 0.36], 'LineWidth', 1.0);
            end
            app.styleAxes(app.SpectrumOutAxes, '处理后频谱', '频率 (Hz)', '幅度 (dB)');
            xlim(app.SpectrumOutAxes, [0 min(app.Fs / 2, 10000)]);
            ylim(app.SpectrumOutAxes, [-100 5]);
        end

        function plotSpectrogram(app)
            cla(app.SpectrogramAxes);
            if isempty(app.YProcessed) || isempty(app.Fs)
                title(app.SpectrogramAxes, '处理后声谱图（处理后显示）');
                return;
            end
            x = app.YProcessed(:);
            maxSamples = min(numel(x), round(30 * app.Fs));
            x = x(1:maxSamples);
            win = min(1024, max(128, 2 ^ floor(log2(max(128, round(0.035 * app.Fs))))));
            hop = max(32, round(win / 4));
            nfft = max(512, 2 ^ nextpow2(win));
            if exist('spectrogram', 'file') == 2
                [s, f, t] = spectrogram(x, hannLocal(win), win - hop, nfft, app.Fs);
            else
                [s, f, t] = VoiceFXApp.localSpectrogram(x, app.Fs, win, hop, nfft);
            end
            imagesc(app.SpectrogramAxes, t, f, 20 * log10(abs(s) + 1e-6));
            axis(app.SpectrogramAxes, 'xy');
            colormap(app.SpectrogramAxes, parula);
            app.styleAxes(app.SpectrogramAxes, '处理后声谱图', '时间 (s)', '频率 (Hz)');
            ylim(app.SpectrogramAxes, [0 min(app.Fs / 2, 10000)]);
        end

        function updateChainDescription(app)
            cfg = makeAppConfig(app.currentSelections());
            lines = {
                ['当前预设：', app.currentPresetName()]
                ['噪声：', app.describeMode('noise', app.NoiseDropDown.Value)]
                ['滤波：', app.describeMode('filter', app.FilterDropDown.Value)]
                ['声线风格：', app.describeMode('voice', app.VoiceDropDown.Value)]
                ['音效：', app.describeMode('fx', app.FxDropDown.Value)]
                ['空间效果：', app.describeMode('space', app.SpaceDropDown.Value)]
                ['AM 模式：', app.describeMode('am', app.AmDropDown.Value)]
                ''
                '说明：App 只负责整理配置和调用既有后端，不在 UI 回调中重写 DSP 算法。'
                sprintf('后端状态：noise=%d, filter=%d, voice=%d, fx=%d, space=%d, AM=%d', ...
                cfg.noise.enabled, cfg.filter.enabled, cfg.voice.enabled, cfg.fx.enabled, cfg.space.enabled, cfg.modDemod.enabled)
                };
            app.ChainArea.Value = lines;
        end

        function name = currentPresetName(app)
            idx = find(strcmp(app.PresetDropDown.ItemsData, app.PresetDropDown.Value), 1);
            if isempty(idx)
                name = '手动选择';
            else
                name = app.PresetDropDown.Items{idx};
            end
        end

        function text = describeMode(~, groupName, mode)
            mode = char(mode);
            switch groupName
                case 'noise'
                    switch mode
                        case 'none', text = 'none，不添加噪声';
                        case 'white', text = 'white，加入轻微白噪声';
                        case 'hum50', text = 'hum50，加入 50 Hz 工频嗡声';
                        case 'impulse', text = 'impulse，加入少量脉冲噪声';
                        otherwise, text = mode;
                    end
                case 'filter'
                    switch mode
                        case 'none', text = 'none，不启用滤波';
                        case 'voice_enhance', text = 'voice_enhance，保留主要语音频段';
                        case 'notch50', text = 'notch50，抑制 50 Hz 工频分量';
                        otherwise, text = [mode, '，传统滤波处理'];
                    end
                case 'voice'
                    switch mode
                        case 'none', text = 'none，不改变声线';
                        case 'male_deep_gentle', text = 'male_deep_gentle，自适应低沉温和男声';
                        case 'female_gentle_sweet', text = 'female_gentle_sweet，自适应柔和甜美女声';
                        case 'child_bright_soft', text = 'child_bright_soft，自适应明亮柔和童声';
                        case 'elder_warm_steady', text = 'elder_warm_steady，自适应温暖稳重老年声';
                        otherwise, text = [mode, ' 声线风格'];
                    end
                case 'fx'
                    switch mode
                        case 'none', text = 'none，不添加设备/数字音效';
                        otherwise, text = [mode, ' 音效'];
                    end
                case 'space'
                    switch mode
                        case 'none', text = 'none，不添加空间感';
                        otherwise, text = [mode, ' 空间效果'];
                    end
                otherwise
                    switch mode
                        case 'off', text = 'off，关闭 AM 演示';
                        case 'modulate', text = 'modulate，AM 调制演示';
                        case 'demodulate', text = 'demodulate，AM 解调演示';
                        otherwise, text = mode;
                    end
            end
        end

        function updateButtonState(app)
            hasInput = ~isempty(app.XOriginal);
            hasOutput = ~isempty(app.YProcessed);
            app.PlayOriginalButton.Enable = VoiceFXApp.onOff(hasInput);
            app.PlayProcessedButton.Enable = VoiceFXApp.onOff(hasOutput);
            app.ProcessButton.Enable = VoiceFXApp.onOff(hasInput);
            app.StopButton.Enable = VoiceFXApp.onOff(hasInput || hasOutput);
            app.SaveButton.Enable = VoiceFXApp.onOff(hasOutput);
        end

        function appendStatus(app, message)
            stamp = datestr(now, 'HH:MM:SS');
            old = app.StatusArea.Value;
            if ischar(old)
                old = {old};
            end
            nextValue = [{[stamp, '  ', char(message)]}; old(:)];
            if numel(nextValue) > 80
                nextValue = nextValue(1:80);
            end
            app.StatusArea.Value = nextValue;
            drawnow limitrate;
        end

        function appendLiveStatus(app, message)
            if isempty(app.LiveStatusArea) || ~isvalid(app.LiveStatusArea)
                return;
            end
            stamp = datestr(now, 'HH:MM:SS');
            old = app.LiveStatusArea.Value;
            if ischar(old)
                old = {old};
            end
            nextValue = [{[stamp, '  ', char(message)]}; old(:)];
            if numel(nextValue) > 40
                nextValue = nextValue(1:40);
            end
            app.LiveStatusArea.Value = nextValue;
            drawnow limitrate;
        end

        function onClose(app)
            app.LiveStopRequested = true;
            app.stopPlayback();
            delete(app.UIFigure);
        end
    end

    methods (Static, Access = private)
        function root = locateProjectRoot()
            here = fileparts(mfilename('fullpath'));
            candidate = fileparts(here);
            if exist(fullfile(candidate, 'core', 'makeDefaultConfig.m'), 'file') == 2
                root = candidate;
            elseif exist(fullfile(pwd, 'core', 'makeDefaultConfig.m'), 'file') == 2
                root = pwd;
            else
                root = candidate;
            end
        end

        function [t, y] = decimateForPlot(x, fs, maxPoints)
            x = double(x(:));
            if isempty(x)
                t = [];
                y = [];
                return;
            end
            step = max(1, ceil(numel(x) / maxPoints));
            idx = 1:step:numel(x);
            y = x(idx);
            t = (idx(:) - 1) / fs;
        end

        function [f, magDb] = makeSpectrum(x, fs)
            x = double(x(:));
            x(~isfinite(x)) = 0;
            if isempty(x)
                f = 0;
                magDb = -120;
                return;
            end
            maxN = min(numel(x), round(20 * fs));
            x = x(1:maxN);
            nfft = max(512, min(32768, 2 ^ nextpow2(numel(x))));
            if numel(x) > 8
                w = hannLocal(numel(x));
                x = x .* w;
            end
            spec = abs(fft(x, nfft));
            count = floor(nfft / 2) + 1;
            spec = spec(1:count);
            f = (0:count-1).' * fs / nfft;
            magDb = 20 * log10(spec / max(max(spec), eps) + 1e-6);
        end

        function [s, f, t] = localSpectrogram(x, fs, win, hop, nfft)
            x = double(x(:));
            frameCount = max(1, 1 + floor((numel(x) - win) / hop));
            if numel(x) < win
                x(end + 1:win, 1) = 0;
                frameCount = 1;
            end
            s = zeros(nfft / 2 + 1, frameCount);
            w = hannLocal(win);
            for k = 1:frameCount
                startIndex = 1 + (k - 1) * hop;
                frame = x(startIndex:startIndex + win - 1) .* w;
                spec = fft(frame, nfft);
                s(:, k) = spec(1:nfft / 2 + 1);
            end
            f = (0:nfft / 2).' * fs / nfft;
            t = ((0:frameCount-1) * hop + win / 2) / fs;
        end

        function value = onOff(tf)
            if tf
                value = 'on';
            else
                value = 'off';
            end
        end

        function pathOut = canonicalPath(pathIn)
            try
                pathOut = char(java.io.File(pathIn).getCanonicalPath());
            catch
                pathOut = char(pathIn);
            end
        end

        function items = normalizeDeviceItems(values)
            if isempty(values)
                items = {};
            elseif iscell(values)
                items = cellfun(@char, values(:).', 'UniformOutput', false);
            elseif isstring(values)
                items = cellstr(values(:).');
            elseif ischar(values)
                items = cellstr(values);
            else
                items = cellstr(string(values(:).'));
            end
        end

        function text = escapeMatlabString(value)
            text = strrep(char(value), '''', '''''');
        end
    end
end

function w = hannLocal(n)
if n <= 1
    w = 1;
else
    idx = (0:n-1).';
    w = 0.5 - 0.5 * cos(2 * pi * idx / (n - 1));
end
end
