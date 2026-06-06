%TEST_07_FILE_DEMO_PIPELINE Validate offline report demo artifact generation.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(genpath(projectRoot));

demoInfo = run_file_demo_pipeline();

assert(isstruct(demoInfo), 'Demo pipeline must return a struct.');
assert(isfield(demoInfo, 'audioFiles'), 'Demo info must include audioFiles.');
assert(isfield(demoInfo, 'figureFiles'), 'Demo info must include figureFiles.');

requiredAudio = {'original', 'filtered', 'voiceFxChain', 'modulated', 'demodulated'};
for k = 1:numel(requiredAudio)
    name = requiredAudio{k};
    assert(isfield(demoInfo.audioFiles, name), ['Missing demo audio field: ', name]);
    pathName = demoInfo.audioFiles.(name);
    assert(exist(pathName, 'file') == 2, ['Expected audio file was not generated: ', pathName]);
    info = audioinfo(pathName);
    assert(info.TotalSamples > 0, ['Generated audio should contain samples: ', pathName]);
end

requiredFigures = {'overview', 'modDemod'};
for k = 1:numel(requiredFigures)
    name = requiredFigures{k};
    assert(isfield(demoInfo.figureFiles, name), ['Missing demo figure field: ', name]);
    pathName = demoInfo.figureFiles.(name);
    assert(exist(pathName, 'file') == 2, ['Expected figure file was not generated: ', pathName]);
end

disp('test_07_file_demo_pipeline passed: offline demo artifacts were generated.');
