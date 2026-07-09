function [runDir, runId, sourceName] = createUniqueResultRun( ...
        projectRoot, inputPath, category)
%CREATEUNIQUERESULTRUN Create a non-overwriting result directory.
%
%   Layout:
%     results/audio/by_source/<source>/<category>/<timestamp>/
%
%   Repeated calls in the same second receive _02, _03, ... suffixes.

if nargin < 1 || isempty(projectRoot)
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(thisFile));
end
if nargin < 2 || isempty(inputPath)
    error('createUniqueResultRun:MissingInput', ...
        'inputPath is required.');
end
if nargin < 3 || isempty(category)
    category = 'pipeline';
end

[~, sourceName, ~] = fileparts(char(inputPath));
sourceName = sanitizeName(sourceName);
category = sanitizeName(category);

baseDir = fullfile(projectRoot, 'results', 'audio', ...
    'by_source', sourceName, category);
if exist(baseDir, 'dir') ~= 7
    mkdir(baseDir);
end

runIdBase = datestr(now, 'yyyymmdd_HHMMSS');
runId = runIdBase;
runDir = fullfile(baseDir, runId);
index = 2;
while exist(runDir, 'dir') == 7
    runId = sprintf('%s_%02d', runIdBase, index);
    runDir = fullfile(baseDir, runId);
    index = index + 1;
end
mkdir(runDir);
end

function name = sanitizeName(name)
name = char(name);
name = regexprep(name, '[<>:"/\\|?*]', '_');
name = regexprep(name, '\s+', '_');
name = regexprep(name, '_+', '_');
name = regexprep(name, '^_+|_+$', '');
if isempty(name)
    name = 'audio';
end
end
