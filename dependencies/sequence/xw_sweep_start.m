function xw_sweep_start()
    % Callback of the 'Voltage sweep' button. Starts a voltage sweep over
    % P.sweep_voltages, P.sweep_passes times, recording P.sweep_frames frames
    % per voltage (P.sweep_save_mode: beamformed images by default, or raw RF)
    % and measuring the mean xAM envelope. Pressing the button during a sweep stops
    % it. The sweep is advanced frame by frame by xw_sweep_frame and ends in
    % xw_sweep_finish, which restores the voltage and plots the result.

    XWSweep = evalin_if_exist('base', 'XWSweep', struct('active', false));
    if XWSweep.active
        fprintf('Sweep stopped by user\n');
        xw_sweep_finish(XWSweep, 'stopped by user');
        return
    end

    P = evalin('base', 'P');
    if ~isfield(P, 'sweep_voltages') || isempty(P.sweep_voltages)
        warndlg('No voltage sweep configured. Start the script with ./run_xam.sh --sweep ...', 'Voltage sweep')
        return
    end
    if evalin_if_exist('base', 'freeze', 0)
        warndlg('Unfreeze the sequence before starting a sweep.', 'Voltage sweep')
        return
    end
    XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
    if XWRecord.active
        warndlg('A recording is running. Wait for it to finish, or press Record to stop it.', 'Voltage sweep')
        return
    end

    if evalin_if_exist('base', 'XWBurst', struct('active', false)).active
        warndlg('A burst is running. Wait for it to finish.', 'Voltage sweep')
        return
    end

    TPC = evalin('base', 'TPC');
    nv = numel(P.sweep_voltages);

    S = struct();
    S.active = true;
    S.mode = P.sweep_save_mode; % independent of the Save mode switch
    S.voltages = P.sweep_voltages(:)';
    S.passes = P.sweep_passes;
    S.frames = P.sweep_frames;
    S.settle_frames = P.sweep_settle_frames;
    S.settle_s = P.sweep_settle_s;
    S.settle_s_down = P.sweep_settle_s_down;
    S.folder = fullfile(P.record_path, [datestr(now, 'yyyymmdd_HHMMSS') '_sweep_' S.mode]); %#ok<TNOW1,DATST>
    S.hv_initial = TPC(1).hv;
    [pass, vi] = ndgrid(1:S.passes, 1:nv);
    S.steps = [reshape(pass', [], 1), reshape(vi', [], 1)]; % [pass, voltage index], pass by pass
    S.step = 1;
    S.hv_set = NaN(S.passes, nv); % voltage actually set
    S.mean_xam = NaN(S.passes, nv, S.frames); % mean |xAM| per frame
    S.mean_bmode = NaN(S.passes, nv, S.frames); % mean |B-mode| per frame (check that the voltage changed)
    S.roi = []; % set on the first measured frame
    S.t_start = datetime('now');
    mkdir(S.folder);
    if strcmp(S.mode, 'rf')
        wait(parfeval(backgroundPool, @() [], 0)); % start background writer threads now
    end

    fprintf('Voltage sweep: %s V, %i passes, %i frames per voltage (%s) to %s\n', ...
        mat2str(S.voltages), S.passes, S.frames, S.mode, S.folder);
    S = xw_sweep_next_step(S);
    assignin('base', 'XWSweep', S);
    xw_burst_update_button();
end
