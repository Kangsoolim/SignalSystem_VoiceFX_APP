function result = runFileMode(inputPath, config, varargin)
%RUNFILEMODE Stable offline entry point for VoiceFX file processing.
%   RESULT = RUNFILEMODE(INPUTPATH, CONFIG) reads an audio file, normalizes
%   it through preprocessAudio, processes it with processAudioFile, and
%   returns a struct suitable for App display/playback/export.
%
%   RESULT = RUNFILEMODE(..., 'OutputPath', PATH, 'Overwrite', TF) also
%   writes the processed audio to PATH. The original input file is never
%   overwritten by this helper.

if nargin < 1 || isempty(inputPath)
    error('runFileMode:MissingInputPath', 'Input audio path is required.');
end
if nargin < 2 || isempty(config)
    config = makeDefaultConfig();
end

opts = parseOptions(varargin{:});
inputPath = char(inputPath);

if exist(inputPath, 'file') ~= 2
    error('runFileMode:FileNotFound', 'Audio file does not exist: %s', inputPath);
end

try
    [xRaw, fs] = audioread(inputPath);
catch ME
    error('runFileMode:ReadFailed', 'Could not read audio file "%s": %s', inputPath, ME.message);
end

if isempty(xRaw)
    error('runFileMode:EmptyAudio', 'Input audio is empty: %s', inputPath);
end
if isempty(fs) || ~isfinite(fs) || fs <= 0
    error('runFileMode:InvalidSampleRate', 'Input audio has an invalid sample rate.');
end

xRaw = double(xRaw);
if ~any(isfinite(xRaw(:)))
    error('runFileMode:InvalidAudio', 'Input audio contains no finite samples.');
end
xRaw(~isfinite(xRaw)) = 0;

xProcessedInput = preprocessAudio(xRaw, fs, config);
if isempty(xProcessedInput)
    error('runFileMode:EmptyAfterPreprocess', 'Input audio became empty after preprocessing.');
end
if ~all(isfinite(xProcessedInput))
    error('runFileMode:InvalidPreprocessedAudio', 'Preprocessed audio contains NaN or Inf.');
end

processingMode = 'frame_pipeline';
processingDiagnostics = struct();
useHighQualityVoice = shouldUseHighQualityVoicePath(config);
try
    if useHighQualityVoice
        [y, ~, processingDiagnostics] = processAudioFileHighQuality(xRaw, fs, config);
        processingMode = 'high_quality_voice';
    else
        y = processAudioFile(xRaw, fs, config);
    end
catch ME
    if ~useHighQualityVoice
        error('runFileMode:ProcessingFailed', 'Audio processing failed: %s', ME.message);
    end

    try
        y = processAudioFile(xRaw, fs, config);
        processingMode = 'frame_pipeline_fallback';
        processingDiagnostics = struct('status', 'fallback', ...
            'highQualityError', ME.message);
    catch fallbackME
        error('runFileMode:ProcessingFailed', ...
            'Audio processing failed. HQ voice error: %s; fallback error: %s', ...
            ME.message, fallbackME.message);
    end
end

y = double(y(:));
if isempty(y)
    error('runFileMode:EmptyOutput', 'Processed audio is empty.');
end
if ~all(isfinite(y))
    error('runFileMode:InvalidOutput', 'Processed audio contains NaN or Inf.');
end

peakBeforeSafety = max(abs(y));
message = '处理完成。';
if peakBeforeSafety > 1.000001
    y = safeLimiter(y, config);
    message = '处理完成；输出峰值已由安全限幅器控制。';
end
if max(abs(y)) > 1.000001
    error('runFileMode:OutputClippingRisk', 'Processed audio still exceeds the safe output range.');
end

result = struct();
result.inputPath = inputPath;
result.fs = fs;
result.xOriginal = preprocessAudio(xRaw, fs, makeNoNormalizeConfig(config));
result.xRaw = xRaw;
result.xProcessedInput = xProcessedInput;
result.y = y;
result.duration = numel(xProcessedInput) / fs;
result.config = config;
result.processingMode = processingMode;
result.processingDiagnostics = processingDiagnostics;
result.message = message;
if strcmp(processingMode, 'frame_pipeline_fallback')
    result.message = [result.message, ' HQ 声线处理失败，已回退到兼容链路。'];
end
result.outputPath = '';

if ~isempty(opts.OutputPath)
    outputPath = char(opts.OutputPath);
    if pathsReferToSameFile(inputPath, outputPath)
        error('runFileMode:RefuseOverwriteInput', 'Refusing to overwrite the original audio file.');
    end
    if exist(outputPath, 'file') == 2 && ~opts.Overwrite
        error('runFileMode:OutputExists', 'Output file already exists: %s', outputPath);
    end

    outputDir = fileparts(outputPath);
    if ~isempty(outputDir) && exist(outputDir, 'dir') ~= 7
        mkdir(outputDir);
    end

    try
        audiowrite(outputPath, y, fs);
    catch ME
        error('runFileMode:WriteFailed', 'Could not write output audio "%s": %s', outputPath, ME.message);
    end
    result.outputPath = outputPath;
    result.message = [result.message, ' 已保存结果。'];
end
end

function tf = shouldUseHighQualityVoicePath(config)
tf = false;
if ~isstruct(config) || ~isfield(config, 'voice') || isempty(config.voice)
    return;
end
voice = config.voice;
enabled = true;
if isfield(voice, 'enabled') && ~isempty(voice.enabled)
    enabled = logicalScalar(voice.enabled);
end
if ~enabled
    return;
end
mode = 'none';
if isfield(voice, 'type') && ~isempty(voice.type)
    mode = char(voice.type);
elseif isfield(voice, 'mode') && ~isempty(voice.mode)
    mode = char(voice.mode);
end
mode = lower(strtrim(mode));
mode = strrep(mode, '-', '_');
mode = strrep(mode, ' ', '_');
switch mode
    case 'male'
        mode = 'male_deep_gentle';
    case 'female'
        mode = 'female_gentle_sweet';
    case 'child'
        mode = 'child_bright_soft';
    case {'elder', 'elderly'}
        mode = 'elder_warm_steady';
end
deepVoiceModes = {'male_deep_gentle', 'female_gentle_sweet', ...
    'child_bright_soft', 'elder_warm_steady'};
tf = any(strcmp(mode, deepVoiceModes)) && ...
    exist('processAudioFileHighQuality', 'file') == 2;
end

function tf = logicalScalar(value)
if islogical(value)
    tf = any(value(:));
elseif isnumeric(value)
    tf = any(value(:) ~= 0);
elseif ischar(value) || isstring(value)
    text = lower(strtrim(char(value)));
    tf = any(strcmp(text, {'true', 'on', 'yes', '1'}));
else
    tf = false;
end
end

function opts = parseOptions(varargin)
opts = struct('OutputPath', '', 'Overwrite', false);
if mod(numel(varargin), 2) ~= 0
    error('runFileMode:InvalidOptions', 'Optional arguments must be name-value pairs.');
end
for k = 1:2:numel(varargin)
    name = lower(char(varargin{k}));
    value = varargin{k + 1};
    switch name
        case 'outputpath'
            opts.OutputPath = value;
        case 'overwrite'
            opts.Overwrite = logical(value);
        otherwise
            error('runFileMode:InvalidOption', 'Unknown option: %s', varargin{k});
    end
end
end

function tf = pathsReferToSameFile(pathA, pathB)
try
    fileA = java.io.File(pathA).getCanonicalPath();
    fileB = java.io.File(pathB).getCanonicalPath();
    tf = strcmpi(char(fileA), char(fileB));
catch
    tf = strcmpi(fullfile(pwd, pathA), fullfile(pwd, pathB));
end
end

function cfg = makeNoNormalizeConfig(config)
cfg = config;
if ~isfield(cfg, 'audio') || isempty(cfg.audio)
    defaults = makeDefaultConfig();
    cfg.audio = defaults.audio;
end
cfg.audio.normalizeInput = false;
cfg.audio.removeDC = false;
end
