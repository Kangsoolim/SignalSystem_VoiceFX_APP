function result = run_v25_configurable_pipeline(inputArg, config)
%RUN_V25_CONFIGURABLE_PIPELINE Run the single switch-controlled course chain.
%
%   Every course module remains an independent switch in ONE pipeline:
%       config.noise.enabled
%       config.filter.enabled
%       config.voice.enabled
%       config.fx.enabled
%       config.space.enabled
%       config.modDemod.enabled
%       config.display.enabled
%
%   Example:
%       config = makeDefaultConfig();
%       config.noise.enabled = true;
%       config.noise.type = 'babble_crowd';
%       config.filter.enabled = true;
%       config.filter.type = 'speech_clean';
%       config.voice.enabled = true;
%       config.voice.type = 'male_deep_gentle';
%       result = run_v25_configurable_pipeline('zongcisheng.wav', config);
%
%   Generated output is placed under results/audio/by_source/<source>/ and
%   never overwrites previous runs.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

if nargin < 1 || isempty(inputArg)
    error('run_v25_configurable_pipeline:MissingInput', ...
        'Provide a full path or a filename in the Voice_test folder.');
end
if nargin < 2 || isempty(config)
    config = makeDefaultConfig();
else
    config = fillPipelineConfig(config);
end

inputPath = resolveVoiceTestInput(inputArg, projectRoot);
[xRaw, fs] = audioread(inputPath);
xDisplay = preprocessAudio(xRaw, fs, config);

[y, state, diagnostics] = processAudioFileHighQuality(xRaw, fs, config);

[runDir, runId, sourceName] = createUniqueResultRun( ...
    projectRoot, inputPath, 'pipeline');
styleName = activeVoiceName(config);
outputName = sprintf('%s__pipeline__%s.wav', sourceName, styleName);
outputPath = fullfile(runDir, outputName);
audiowrite(outputPath, safeAudio(y), fs);

plotInfo = struct();
if logical(config.display.enabled) || logical(config.display.saveFigure)
    displayConfig = config.display;
    displayConfig.outputDir = runDir;
    displayConfig.figureName = [sourceName, '__signal_info.png'];
    plotInfo = plotSignalInfo(xDisplay, y, fs, displayConfig);
end

metadataPath = fullfile(runDir, 'run_metadata.mat');
save(metadataPath, 'config', 'diagnostics', 'plotInfo');

result = struct();
result.inputPath = inputPath;
result.sourceName = sourceName;
result.sampleRate = fs;
result.runId = runId;
result.runDir = runDir;
result.outputPath = outputPath;
result.metadataPath = metadataPath;
result.state = state;
result.diagnostics = diagnostics;
result.plotInfo = plotInfo;
result.moduleSwitches = struct( ...
    'noise', logical(config.noise.enabled), ...
    'filter', logical(config.filter.enabled), ...
    'voice', logical(config.voice.enabled), ...
    'fx', logical(config.fx.enabled), ...
    'space', logical(config.space.enabled), ...
    'modDemod', logical(config.modDemod.enabled), ...
    'display', logical(config.display.enabled));

fprintf('Pipeline finished. Output preserved at:\n%s\n', outputPath);
end


function config = fillPipelineConfig(config)
defaults = makeDefaultConfig();
fields = fieldnames(defaults);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(config, name) || isempty(config.(name))
        config.(name) = defaults.(name);
    elseif isstruct(config.(name)) && isstruct(defaults.(name))
        subFields = fieldnames(defaults.(name));
        for j = 1:numel(subFields)
            subName = subFields{j};
            if ~isfield(config.(name), subName)
                config.(name).(subName) = defaults.(name).(subName);
            end
        end
    end
end
end

function name = activeVoiceName(config)
name = 'voice_bypass';
if isfield(config, 'voice') && isstruct(config.voice) && ...
        isfield(config.voice, 'enabled') && config.voice.enabled
    if isfield(config.voice, 'type') && ~isempty(config.voice.type)
        name = char(config.voice.type);
    elseif isfield(config.voice, 'mode') && ~isempty(config.voice.mode)
        name = char(config.voice.mode);
    else
        name = 'voice_enabled';
    end
end
name = regexprep(name, '[^A-Za-z0-9_\-]', '_');
end

function y = safeAudio(x)
y = double(x(:));
y(~isfinite(y)) = 0;
peak = max(abs(y));
if peak > 0.98
    y = 0.98*y/peak;
end
end
