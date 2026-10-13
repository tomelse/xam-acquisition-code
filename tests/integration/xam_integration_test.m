% Integration test: runs xAM_imaging.m in VSX and lets a timer
% (xam_integration_driver) press every control and check the result, without
% user input. Started by tests/run_tests.sh, which activates the Verasonics
% software first and sets the XAM_* environment variables (simulation or
% hardware, test data folder, sweep). Exits MATLAB with code 0 if all checks
% passed, 1 otherwise.
%
% State is kept in getappdata(groot, 'xamtest'), since xAM_imaging.m starts
% with 'clear all'.

xamtest_repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
setappdata(groot, 'xamtest', struct( ...
    'repo', xamtest_repo, ...
    'out', getenv('XAM_DATA_PATH'), ...
    'hardware', ~strcmp(getenv('XAM_SIMULATE'), '1'), ...
    'sweep', ~isempty(getenv('XAM_SWEEP_VOLTAGES')), ...
    't0', tic));
setappdata(groot, 'xamtest_dialogs', {});
delete(timerfindall('Tag', 'xamtest'));
start(timer('Tag', 'xamtest', 'ExecutionMode', 'fixedSpacing', 'Period', 0.25, ...
    'TimerFcn', @(~, ~) xam_integration_driver()));
start(timer('Tag', 'xamtest', 'ExecutionMode', 'fixedSpacing', 'Period', 0.5, ...
    'TimerFcn', @(~, ~) xam_integration_driver('dialogs')));

try
    run(fullfile(xamtest_repo, 'xAM_imaging.m'));
catch xamtest_err
    fprintf(2, '[TEST] xAM_imaging.m failed: %s\n', getReport(xamtest_err, 'extended', 'hyperlinks', 'off'));
end

delete(timerfindall('Tag', 'xamtest'));
xamtest_code = xam_integration_driver('report');
exit(xamtest_code);
