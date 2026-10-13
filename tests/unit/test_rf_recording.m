function tests = test_rf_recording
    % Unit tests for raw RF recording (xw_record_begin / xw_record_frame /
    % background writes) and xw_load_rf_recording, without VSX. The
    % recording functions read P and Resource from the base workspace, so
    % small stand-ins are put there.
    tests = functiontests(localfunctions);
end

function setupOnce(t)
    t.TestData.folder = tempname;
    rows = 3 * 4 * 64; % 3 pulses x 4 rays x 64 samples
    P = struct('fps', 2, 'num_rf_frames', 4, 'ray_positions', 1:4, 'image_start_depth_mm', 0, ...
        'image_end_depth_mm', 1, 'scale_wvl2mm', 0.1, 'beamform_image_modes', {{'PW', 'xAM'}}, ...
        'record_path', t.TestData.folder);
    Resource.RcvBuffer(1) = struct('rowsPerFrame', rows, 'colsPerFrame', 128);
    t.TestData.saved = struct('P', base_get('P'), 'Resource', base_get('Resource'), 'XWRecord', base_get('XWRecord'));
    assignin('base', 'P', P);
    assignin('base', 'Resource', Resource);
    rng(1);
    t.TestData.frames = arrayfun(@(~) int16(randi([-3000 3000], rows, 128)), 1:4, 'UniformOutput', false);
end

function teardownOnce(t)
    for f = fieldnames(t.TestData.saved)'
        if isempty(t.TestData.saved.(f{1})), evalin('base', ['clear ' f{1}]);
        else, assignin('base', f{1}, t.TestData.saved.(f{1})); end
    end
    if isfolder(t.TestData.folder), rmdir(t.TestData.folder, 's'); end
end

function test_round_trip(t)
    folder = fullfile(t.TestData.folder, 'round_trip');
    verifyTrue(t, xw_record_begin('rf', 3, folder));
    for k = 1:4 % 4th frame must not be recorded
        xw_record_frame(t.TestData.frames{k}, struct('TimeTag', k));
    end
    wait_for_finish(folder, 3);
    [RF, info] = xw_load_rf_recording(folder);
    verifyEqual(t, RF, cat(3, t.TestData.frames{1:3}));
    verifyEqual(t, info.time_tags, [1 2 3]);
    verifyEmpty(t, info.failed_frames);
    verifyEqual(t, xw_load_rf_recording(folder, [3 1]), cat(3, t.TestData.frames{[3 1]}));
end

function test_failed_write_stops_recording(t)
    folder = fullfile(t.TestData.folder, 'failed');
    verifyTrue(t, xw_record_begin('rf', 4, folder));
    mkdir(fullfile(folder, 'frame_00002.bin')); % a folder in the way: frame 2 cannot be written
    for k = 1:4
        xw_record_frame(t.TestData.frames{k}, struct('TimeTag', k));
        pause(0.2);
        R = evalin('base', 'XWRecord');
        if ~R.active, break; end
    end
    verifyFalse(t, R.active, 'recording should stop after a failed write');
    pause(1); drawnow;
    info = load(fullfile(folder, 'recording_info.mat'));
    verifyEqual(t, info.failed_frames, 2);
    verifyEqual(t, xw_load_rf_recording(folder), t.TestData.frames{1});
    verifyError(t, @() xw_load_rf_recording(folder, 2), ?MException);
end

function wait_for_finish(folder, n)
    t0 = tic;
    while toc(t0) < 30
        pause(0.1); drawnow;
        f = fullfile(folder, 'recording_info.mat');
        if isfile(f)
            s = load(f);
            if s.num_frames == n && isfield(s, 'failed_frames'), return; end
        end
    end
    error('recording in %s did not finish', folder);
end

function v = base_get(name)
    v = [];
    if evalin('base', sprintf('exist(''%s'', ''var'')', name)), v = evalin('base', name); end
end
