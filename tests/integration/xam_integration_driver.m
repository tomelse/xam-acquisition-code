function out = xam_integration_driver(cmd)
    % Timer callback that drives the VSX GUI through all features and checks
    % each one. xam_integration_driver('report') prints the results and
    % returns the exit code (0 = all passed). xam_integration_driver('dialogs')
    % closes message/error/warning dialogs (some block with uiwait) and logs them.
    %
    % Each step is a local function step_<name>(T) that returns
    % [T, status, message] with status 'running', 'pass' or 'fail'. Steps use
    % the real GUI controls (buttons, sliders, button group) where possible.

    T = getappdata(groot, 'xamtest');
    if nargin && strcmp(cmd, 'report')
        out = report(T);
        return
    end
    if nargin && strcmp(cmd, 'dialogs')
        close_dialogs();
        return
    end
    if ~isfield(T, 'steps') % first call
        T.steps = {'wait_for_gui', 'start_sequence', 'persistence', 'dynamic_range', 'save_mode', ...
            'record_images', 'record_rf', 'record_stop_early', 'burst', 'freeze', 'save_data_images', ...
            'save_data_rf', 'offline_reconstruction'};
        if T.sweep, T.steps{end + 1} = 'voltage_sweep'; end
        if T.hardware, T.steps(end + 1:end + 3) = {'time_tags', 'chunk_timing', 'frame_rate'}; end
        T.steps{end + 1} = 'close_vsx';
        T.k = 1; T.phase = 0; T.t = tic; T.frames = 0; T.sig = NaN; T.busy = false;
        T.results = struct('name', {}, 'status', {}, 'message', {}, 'seconds', {});
    end
    if T.busy || T.k > numel(T.steps), return; end
    T.busy = true; setappdata(groot, 'xamtest', T); % no re-entry while a step runs

    T = count_frames(T);
    name = T.steps{T.k};
    try
        [T, status, msg] = feval(['step_' name], T);
        if strcmp(status, 'running') && toc(T.t) > step_timeout(name)
            status = 'fail'; msg = sprintf('timed out after %.0f s (%s)', toc(T.t), msg);
        end
    catch e
        status = 'fail'; msg = e.message;
        if ~strcmp(e.identifier, 'xamtest:check') && ~isempty(e.stack) % unexpected error: say where
            msg = sprintf('%s (%s, line %i)', msg, e.stack(1).name, e.stack(1).line);
        end
    end
    if ~strcmp(status, 'running')
        T.results(end + 1) = struct('name', name, 'status', status, 'message', msg, 'seconds', toc(T.t));
        fprintf('[TEST] %-18s %s  %s\n', name, upper(status), msg);
        T = cleanup_after_failure(T, status);
        T.k = T.k + 1; T.phase = 0; T.t = tic;
        if strcmp(name, 'wait_for_gui') && strcmp(status, 'fail'), T.k = numel(T.steps); end % nothing else can run
    end
    T.busy = false;
    setappdata(groot, 'xamtest', T);
end

%% ------------------------------------------------------------------ steps

function [T, status, msg] = step_wait_for_gui(T)
    status = 'running'; msg = 'waiting for VSX';
    if ~isempty(ctrl('UserB1PushButton')) && evalin('base', 'exist(''Control'', ''var'')')
        status = 'pass'; msg = 'VSX control panel is up';
    end
end

function [T, status, msg] = step_start_sequence(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            press('UserB1PushButton'); T.f0 = T.frames; T.phase = 1;
        case 1
            msg = sprintf('%i frames so far', T.frames - T.f0);
            if T.frames - T.f0 >= 3, status = 'pass'; msg = sprintf('acquiring, %i frames processed', T.frames - T.f0); end
    end
end

function [T, status, msg] = step_persistence(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            set_slider('UserB6Slider', 0.5); T.f0 = T.frames; T.phase = 1;
        case 1
            if T.frames - T.f0 < 2, return; end
            check(base('UISTATES.persistence') == 0.5, 'UISTATES.persistence is not 0.5');
            d = max(abs(base('BFData.xAM(:)') - base('BFData_raw.xAM(:)')));
            set_slider('UserB6Slider', 1);
            check(d > 0, 'BFData equals BFData_raw: persistence not applied');
            status = 'pass'; msg = 'slider sets persistence, BFData is blended';
    end
end

function [T, status, msg] = step_dynamic_range(T)
    [T, status, msg] = wait_phase(T);
    set_slider('UserC6Slider', 50);
    set_slider('UserC5Slider', 25);
    check(base('UISTATES.dr_bmode') == 50 && base('UISTATES.dr_xam') == 25, 'UISTATES not updated');
    clims = get(findall(groot, 'Type', 'axes'), {'CLim'});
    clims = vertcat(clims{:});
    check(ismember([-50 0], clims, 'rows') && ismember([-25 0], clims, 'rows'), 'image colour limits not updated');
    set_slider('UserC6Slider', 40);
    set_slider('UserC5Slider', 20);
    status = 'pass'; msg = 'DR B-Mode and DR xAM update the display';
end

function [T, status, msg] = step_save_mode(T)
    [T, status, msg] = wait_phase(T);
    select_save_mode('rf');
    check(strcmp(base('UISTATES.save_mode'), 'rf'), 'Raw RF button did not set save mode');
    select_save_mode('images');
    check(strcmp(base('UISTATES.save_mode'), 'images'), 'xAM images button did not set save mode');
    status = 'pass'; msg = 'switch sets images / rf';
end

function [T, status, msg] = step_record_images(T)
    [T, status, msg, folder] = record_step(T, 'images', 3);
    if strcmp(status, 'pass')
        for k = 1:3
            f = load(fullfile(folder, sprintf('frame_%05i.mat', k)));
            check(isfield(f, 'BFData') && isfield(f.BFData, 'xAM'), 'frame file without BFData.xAM');
        end
        msg = '3 image frames saved';
    end
end

function [T, status, msg] = step_record_rf(T)
    [T, status, msg, folder] = record_step(T, 'rf', 3);
    if strcmp(status, 'pass')
        [RF, info] = xw_load_rf_recording(folder);
        check(size(RF, 3) == 3, 'expected 3 RF frames, got %i', size(RF, 3));
        check(isequal(size(RF, [1 2]), info.frame_size), 'RF frame size does not match recording_info');
        check(~isequal(RF(:, :, 1), RF(:, :, 2)), 'RF frames 1 and 2 are identical');
        msg = sprintf('3 RF frames saved and loaded (%s)', mat2str(size(RF)));
        T.rf_folder = folder; % reconstructed offline in step_offline_reconstruction
    end
end

function [T, status, msg] = step_record_stop_early(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            select_save_mode('images'); set_slider('UserC3Slider', 20);
            press('UserC2PushButton'); T.phase = 1;
        case 1
            R = base('XWRecord');
            if R.frame_count >= 2
                check(strcmp(ctrl('UserC4PushButton').Enable, 'off'), 'Burst button is enabled during a recording');
                press('UserC2PushButton'); T.folder = R.folder; T.phase = 2;
            end
        case 2
            if base('XWRecord.active') || ~finished(T.folder), return; end
            info = load(fullfile(T.folder, 'recording_info.mat'));
            check(info.num_frames >= 2 && info.num_frames < 20, 'expected 2-19 frames, got %i', info.num_frames);
            status = 'pass'; msg = sprintf('stopped after %i of 20 frames', info.num_frames);
    end
end

function [T, status, msg] = step_burst(T)
    % one burst: the Burst button is disabled while it runs, the frames and the
    % voltages are saved, and live imaging continues afterwards
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            if base('XWRecord.active') || ~strcmp(ctrl('UserC4PushButton').Enable, 'on'), msg = 'waiting for the Burst button'; return; end
            press('UserC4PushButton');
            check(base('XWBurst.active'), 'XWBurst.active is not set after pressing Burst');
            check(strcmp(ctrl('UserC4PushButton').Enable, 'off'), 'Burst button not disabled during the burst');
            T.folder = base('XWBurst.folder'); T.phase = 1;
        case 1
            msg = sprintf('burst running, %i of %i images saved', base('XWBurst.image_count'), base('XWBurst.num_frames'));
            check(strcmp(ctrl('UserC4PushButton').Enable, 'off') || ~base('XWBurst.active'), 'Burst button enabled during the burst');
            if base('XWBurst.active'), return; end
            T.f0 = T.frames; T.phase = 2;
        case 2
            if T.frames - T.f0 < 3, msg = 'waiting for live imaging to resume'; return; end
            check(strcmp(ctrl('UserC4PushButton').Enable, 'on'), 'Burst button not enabled after the burst');
            B = load(fullfile(T.folder, 'burst.mat'));
            n = base('P.burst_pre_frames') + base('P.burst_collapse_frames') + base('P.burst_post_frames');
            check(strcmp(B.status, 'complete'), 'burst status: %s', B.status);
            check(size(B.images, 3) == n, 'expected %i burst frames, got %i', n, size(B.images, 3));
            check(all(isfinite(B.images(:))) && any(B.images(:) > 0) && ~isequal(B.images(:, :, 1), B.images(:, :, 2)), 'burst images are empty or identical');
            check(size(B.images, 2) == numel(B.x_axis) && size(B.images, 1) == numel(B.z_axis), 'image size does not match the axes');
            check(isequal(B.tpc_profile, [ones(1, base('P.burst_pre_frames')), 2 * ones(1, base('P.burst_collapse_frames')), ones(1, base('P.burst_post_frames'))]), ...
                'TPC profiles of the frames: %s', mat2str(B.tpc_profile));
            check(isfile(fullfile(T.folder, 'burst.png')) && isfile(fullfile(T.folder, 'acq_parameters.mat')), 'burst.png or acq_parameters.mat missing');
            status = 'pass'; msg = sprintf('%i frames saved (%i at %.1f V), live imaging resumed', n, base('P.burst_collapse_frames'), base('P.burst_voltage'));
            if T.hardware && abs(base('P.burst_voltage') - base('TPC(1).hv')) > 0.5
                % the image amplitude is proportional to the transmit voltage: the voltage was switched
                m = squeeze(mean(B.images, [1 2]))';
                ratio = mean(m(B.tpc_profile == 2)) / mean(m(B.tpc_profile == 1));
                expected = base('P.burst_voltage') / base('TPC(1).hv');
                check(abs(ratio / expected - 1) < 0.3, 'image level at the burst voltage is %.2f x the imaging level, expected about %.2f', ratio, expected);
                msg = sprintf('%s; image level %.2f x at the burst voltage (expected %.2f)', msg, ratio, expected);
            end
    end
end

function [T, status, msg] = step_freeze(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            set_freeze(1); T.phase = 1; T.tp = tic;
        case 1
            if toc(T.tp) < 2, return; end % let a frame in flight finish
            T.f0 = T.frames; T.phase = 2; T.tp = tic;
        case 2
            if toc(T.tp) < 3, return; end
            check(T.frames == T.f0, '%i frames processed while frozen', T.frames - T.f0);
            set_freeze(0); T.f0 = T.frames; T.phase = 3;
        case 3
            if T.frames - T.f0 >= 2, status = 'pass'; msg = 'no frames while frozen, resumes after unfreeze'; end
    end
end

function [T, status, msg] = step_save_data_images(T)
    [T, status, msg] = save_data_step(T, 'images', 'BFData');
end

function [T, status, msg] = step_save_data_rf(T)
    [T, status, msg] = save_data_step(T, 'rf', 'RcvData');
end

function [T, status, msg] = step_offline_reconstruction(T)
    % 1) the RF snapshot holds the 4 buffer frames and the live image of the last
    %    processed one: offline reconstruction must reproduce it
    S = load(fullfile(T.out, 'snapshots', 'snapshot_rf.mat'), 'P', 'Receive', 'Trans', 'TW', 'RcvData', 'BFData_raw');
    check(isfield(S, 'BFData_raw') && isfield(S, 'RcvData'), 'RF snapshot without BFData_raw or RcvData');
    check(S.P.num_chunks > 1, 'the live view did not reconstruct in chunks (P.num_chunks = %i)', S.P.num_chunks);
    R = xw_reconstruct_setup(S.P, S.Receive, S.Trans, S.TW);
    d = inf(1, size(S.RcvData{1}, 3));
    for f = 1:numel(d)
        B = xw_reconstruct_frame(R, S.RcvData{1}(:, :, f));
        d(f) = max(cellfun(@(m) max(abs(B.(m)(:) - S.BFData_raw.(m)(:))) / max(abs(S.BFData_raw.(m)(:))), R.modes));
    end
    [dmin, fbest] = min(d);
    check(dmin < 1e-6, 'no buffer frame reproduces the live image (smallest difference %.2g)', dmin);
    % 2) the example script on the RF recording made in step_record_rf
    check(isfield(T, 'rf_folder'), 'no RF recording from step record_rf');
    E = run_reconstruct_example(fullfile(T.repo, 'examples', 'reconstruct_rf.m'), T.rf_folder);
    check(size(E.images.xAM, 3) == 3 && size(E.images_dB.PW, 3) == 3, 'example script did not reconstruct 3 frames');
    check(isgraphics(E.fig), 'example script did not show the images');
    close(E.fig);
    status = 'pass';
    msg = sprintf('buffer frame %i matches the live image (difference %.1g); example script made a 3-frame stack', fbest, dmin);
end

function [T, status, msg] = step_voltage_sweep(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            T.hv0 = base('TPC(1).hv');
            press('UserB2PushButton'); T.phase = 1; T.tp = tic;
        case 1
            msg = 'sweeping';
            if toc(T.tp) < 2 || base('XWSweep.active'), return; end
            % the sweep is marked inactive before its results are saved and plotted
            S = base('XWSweep');
            msg = 'waiting for sweep results';
            if ~isfile(fullfile(S.folder, 'sweep_results.png')), return; end
            R = load(fullfile(S.folder, 'sweep_results.mat'));
            check(strcmp(R.status, 'complete'), 'sweep status: %s', R.status);
            check(all(abs(R.hv_set - R.voltages_requested) < 0.05, 'all'), 'voltages set %s differ from requested %s', ...
                mat2str(R.hv_set), mat2str(R.voltages_requested));
            check(all(isfinite(R.mean_xam(:))), 'missing xAM measurements');
            check(abs(base('TPC(1).hv') - T.hv0) < 0.05, 'voltage not restored: %.2f V instead of %.2f V', base('TPC(1).hv'), T.hv0);
            check(abs(ctrl('hv1Sldr').Value - T.hv0) < 0.05, 'High Voltage slider not restored');
            status = 'pass';
            msg = sprintf('%i voltages x %i passes, voltage restored to %.1f V', numel(R.voltages_requested), size(R.hv_set, 1), T.hv0);
    end
end

function [T, status, msg] = step_time_tags(T)
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            T.tags = []; T.f0 = T.frames; T.phase = 1;
        case 1
            if T.frames > T.f0, T.tags(end + 1) = base('BFData_raw.TimeTag'); T.f0 = T.frames; end
            if numel(T.tags) < 4, return; end
            check(all(diff(T.tags) > 0), 'time tags not increasing: %s', mat2str(T.tags, 4));
            status = 'pass'; msg = sprintf('time tags increase, mean frame interval %.3f s', mean(diff(T.tags)));
    end
end

function [T, status, msg] = step_chunk_timing(T)
    % Hardware only: time tags of the acquisitions in the RF snapshot show whether
    % the chunk transfers (sub-frame DMA) disturb the acquisition timing
    S = load(fullfile(T.out, 'snapshots', 'snapshot_rf.mat'), 'P', 'RcvData');
    C = xw_chunk_timing(S.P, S.RcvData{1});
    check(C.increasing, 'time tags of the acquisitions do not increase');
    check(abs(C.within_chunk - C.ttna) < 1.5 * 25e-6, 'acquisitions within a chunk are %.0f us apart, expected ttna = %.0f us', ...
        C.within_chunk * 1e6, C.ttna * 1e6);
    status = 'pass';
    msg = sprintf('%i chunks: within a chunk %.0f us apart (ttna %.0f); extra pause at chunk boundaries %.0f us (max %.0f); frame acquired in %.2f ms instead of %.2f ms', ...
        C.num_chunks, C.within_chunk * 1e6, C.ttna * 1e6, mean(C.pause) * 1e6, max(C.pause) * 1e6, C.span * 1e3, C.span_expected * 1e3);
end

function [T, status, msg] = step_frame_rate(T)
    % Hardware only: the achieved frame rate (from the time tags) must be P.fps.
    % Set a rate close to P.max_framerate with run_tests.sh --fps
    [T, status, msg] = wait_phase(T);
    switch T.phase
        case 0
            T.tags = []; T.f0 = T.frames; T.phase = 1;
        case 1
            if T.frames > T.f0, T.tags(end + 1) = base('BFData_raw.TimeTag'); T.f0 = T.frames; end
            msg = sprintf('%i frames so far', numel(T.tags));
            if numel(T.tags) < 20, return; end
            fps = 1 / mean(diff(T.tags));
            P_fps = base('P.fps'); P_max = base('P.max_framerate');
            check(abs(fps / P_fps - 1) < 0.05, 'frame rate is %.2f Hz, requested %.2f Hz (maximum %.1f Hz); slowest frame interval %.1f ms', ...
                fps, P_fps, P_max, max(diff(T.tags)) * 1e3);
            status = 'pass';
            msg = sprintf('%.2f Hz achieved, %.2f Hz requested (maximum %.1f Hz, %i chunks)', fps, P_fps, P_max, base('P.num_chunks'));
    end
end

function [T, status, msg] = step_close_vsx(T)
    status = 'pass'; msg = 'closing VSX';
    close(ancestor(ctrl('UserB1PushButton'), 'figure'));
end

%% ---------------------------------------------------------- step helpers

function [T, status, msg, folder] = record_step(T, mode, n)
    % press Record in the given save mode and wait for n frames
    [T, status, msg] = wait_phase(T);
    folder = '';
    switch T.phase
        case 0
            select_save_mode(mode); set_slider('UserC3Slider', n);
            check(base('UISTATES.record_num_frames') == n, 'Rec. frames slider did not set %i', n);
            press('UserC2PushButton'); T.phase = 1; T.tp = tic;
        case 1
            msg = 'recording';
            if toc(T.tp) < 1, return; end
            R = base('XWRecord');
            if R.active || ~finished(R.folder), return; end
            info = load(fullfile(R.folder, 'recording_info.mat'));
            check(info.num_frames == n, 'expected %i frames, got %i', n, info.num_frames);
            if isfield(info, 'failed_frames'), check(isempty(info.failed_frames), 'failed frames %s', mat2str(info.failed_frames)); end
            folder = R.folder; status = 'pass';
    end
end

function [T, status, msg] = save_data_step(T, mode, variable)
    % freeze, Save Data in the given mode, check the file, close the menu, unfreeze
    [T, status, msg] = wait_phase(T);
    fn = sprintf('snapshot_%s.mat', mode);
    switch T.phase
        case 0
            set_freeze(1); select_save_mode(mode); T.phase = 1; T.tp = tic;
            % close the menu after saving instead of showing the modal 'Data
            % saved!' box, which blocks this timer callback (and all other timers)
            evalin('base', 'SaveDataMenuSettings.keep_open = false;');
        case 1
            if toc(T.tp) < 2, return; end
            press('UserC1PushButton'); T.phase = 2;
        case 2
            menu = findall(groot, 'Tag', 'SaveDataMenu');
            if isempty(menu), msg = 'waiting for save menu'; return; end
            fields = findall(menu, 'Type', 'uieditfield');
            for f = reshape(fields, 1, [])
                if endsWith(f.Value, '.mat'), f.Value = fn; else, f.Value = fullfile(T.out, 'snapshots'); end
            end
            b = findall(menu, 'Type', 'uibutton', 'Text', 'Save');
            b.ButtonPushedFcn(b, []);
            file = fullfile(T.out, 'snapshots', fn);
            check(isfile(file), 'snapshot %s not written', file);
            vars = who('-file', file);
            check(ismember(variable, vars), '%s missing from snapshot (has: %s)', variable, strjoin(vars, ', '));
            delete(findall(groot, 'Tag', 'SaveDataMenu'));
            set_freeze(0); T.f0 = T.frames; T.phase = 3; T.msg = sprintf('%s saved with %s', fn, variable);
        case 3
            if T.frames - T.f0 >= 2, status = 'pass'; msg = T.msg; end
    end
end

function [T, status, msg] = wait_phase(T)
    status = 'running'; msg = sprintf('phase %i', T.phase);
end

function T = cleanup_after_failure(T, status)
    % leave the GUI in a usable state for the next step
    if ~strcmp(status, 'fail'), return; end
    try
        if base('XWRecord.active'), press('UserC2PushButton'); end
        if evalin('base', 'exist(''freeze'', ''var'') && freeze == 1'), set_freeze(0); end
        delete(findall(groot, 'Tag', 'SaveDataMenu'));
    catch
    end
end

function T = count_frames(T)
    % a new frame changes BFData_raw (moving points in simulation, noise on hardware)
    try
        B = evalin('base', 'BFData_raw');
        sig = sum(abs(double(B.xAM(:)))) + double(B.TimeTag);
        if ~isequaln(sig, T.sig), T.sig = sig; T.frames = T.frames + 1; end
    catch
    end
end

function ok = finished(folder)
    % recording_info.mat gets 'failed_frames' (RF) or the final count when a recording is finished
    f = fullfile(folder, 'recording_info.mat');
    ok = false;
    if isfile(f)
        s = load(f);
        ok = s.num_frames > 0 && (isfield(s, 'failed_frames') || strcmp(s.mode, 'images'));
    end
end

function s = step_timeout(name)
    s = 120;
    if strcmp(name, 'voltage_sweep'), s = 600; end
    if strcmp(name, 'wait_for_gui'), s = 180; end
end

%% ------------------------------------------------------------- GUI helpers

function h = ctrl(tag)
    h = findall(groot, 'Tag', tag);
end

function press(tag)
    h = ctrl(tag);
    check(~isempty(h), 'control %s not found', tag);
    fire(h(1));
end

function set_slider(tag, value)
    h = ctrl(tag);
    check(~isempty(h), 'slider %s not found', tag);
    h(1).Value = value;
    fire(h(1));
end

function set_freeze(value)
    h = ctrl('FreezeButton');
    check(~isempty(h), 'Freeze button not found');
    h(1).Value = value;
    fire(h(1));
end

function select_save_mode(mode)
    % select the radio button of the Save mode group, as a click would
    labels = struct('images', 'xAM images', 'rf', 'Raw RF');
    g = findall(groot, 'Type', 'uibuttongroup');
    r = findall(g, 'Style', 'radiobutton', 'String', labels.(mode));
    check(~isempty(r), 'Save mode button "%s" not found', labels.(mode));
    old = g.SelectedObject;
    g.SelectedObject = r;
    evt = struct('NewValue', r, 'OldValue', old, 'Source', g, 'EventName', 'SelectionChanged');
    g.SelectionChangedFcn(g, evt);
end

function fire(h)
    cb = h.Callback;
    if isa(cb, 'function_handle'), cb(h, []);
    elseif iscell(cb), feval(cb{1}, h, [], cb{2:end});
    elseif ischar(cb), evalin('base', cb);
    end
end

function v = base(expr)
    v = evalin('base', expr);
end

function check(cond, varargin)
    if ~cond, error('xamtest:check', varargin{:}); end
end

%% ----------------------------------------------------------------- dialogs

function close_dialogs()
    % Close msgbox/errordlg/warndlg windows and log their text. Runs on its own
    % timer, so it also closes dialogs that block the driver with uiwait.
    figs = findall(groot, 'Type', 'figure');
    figs = figs(startsWith(get(figs, {'Tag'}), 'Msgbox_'));
    for f = reshape(figs, 1, [])
        txt = get(findall(f, 'Type', 'text'), 'String');
        if iscell(txt), txt = strjoin(cellfun(@(x) strjoin(cellstr(x), ' '), txt, 'UniformOutput', false), ' '); end
        txt = strjoin(cellstr(txt), ' ');
        D = getappdata(groot, 'xamtest_dialogs');
        D{end + 1} = sprintf('%s: %s', f.Name, txt); %#ok<AGROW>
        setappdata(groot, 'xamtest_dialogs', D);
        fprintf('[TEST] dialog closed: "%s: %s"\n', f.Name, txt);
        delete(f);
    end
end

%% ------------------------------------------------------------------ report

function code = report(T)
    if ~isfield(T, 'results'), T.results = struct('name', {}, 'status', {}, 'message', {}, 'seconds', {}); T.steps = {}; T.k = 1; end
    for k = T.k:numel(T.steps) % steps that never ran (VSX closed or crashed)
        T.results(end + 1) = struct('name', T.steps{k}, 'status', 'fail', 'message', 'did not run', 'seconds', 0);
    end
    if isempty(T.results)
        T.results = struct('name', 'vsx', 'status', 'fail', 'message', 'VSX never started', 'seconds', 0);
    end
    % dialogs other than the expected 'Data saved!' mean a control refused an action
    D = getappdata(groot, 'xamtest_dialogs');
    unexpected = D(~contains(D, 'Data saved!'));
    if ~isempty(unexpected)
        T.results(end + 1) = struct('name', 'dialogs', 'status', 'fail', 'message', strjoin(unexpected, ' | '), 'seconds', 0);
    end
    n_fail = nnz(strcmp({T.results.status}, 'fail'));
    fprintf('\n[TEST] ================= integration test summary (%s) =================\n', ...
        ternary(T.hardware, 'hardware', 'simulation'));
    for r = T.results
        fprintf('[TEST] %-4s %-18s %5.1f s  %s\n', upper(r.status), r.name, r.seconds, r.message);
    end
    fprintf('[TEST] %i passed, %i failed, %.0f s in total\n', numel(T.results) - n_fail, n_fail, toc(T.t0));
    code = double(n_fail > 0);
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
