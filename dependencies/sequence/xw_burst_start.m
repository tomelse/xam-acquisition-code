function xw_burst_start(confirm)
    % Callback of the 'Burst' button. Acquires one burst: P.burst_pre_frames
    % frames at the imaging voltage, P.burst_collapse_frames frames at the burst
    % voltage (TPC profile 2, the 'High Voltage P2' slider; collapses gas
    % vesicles) and P.burst_post_frames frames at the imaging voltage, with
    % focused transmits at a high frame rate. The burst is a separate block of
    % events in the sequence (see xAM_imaging.m) that starts here. The images
    % are reconstructed and collected by xw_burst_save_image at the end of the
    % burst, and xw_burst_finish saves them and returns to live imaging.
    %
    % xw_burst_start(false) skips the confirmation (P.burst_confirm).

    P = evalin('base', 'P');
    if nargin < 1, confirm = P.burst_confirm; end

    if evalin_if_exist('base', 'freeze', 1)
        warndlg('Press Start Seq. (or unfreeze the sequence) before starting a burst.', 'Burst')
        return
    end
    if evalin_if_exist('base', 'XWBurst', struct('active', false)).active
        return
    end
    if evalin_if_exist('base', 'XWRecord', struct('active', false)).active
        warndlg('A recording is running. Wait for it to finish, or press Record to stop it.', 'Burst')
        return
    end
    if evalin_if_exist('base', 'XWSweep', struct('active', false)).active
        warndlg('A voltage sweep is running. Press Voltage sweep to stop it first.', 'Burst')
        return
    end

    TPC = evalin('base', 'TPC');
    Trans = evalin('base', 'Trans');
    plan = xw_burst_plan(P.burst_pre_frames, P.burst_collapse_frames, P.burst_post_frames);
    if TPC(2).hv > Trans.maxHighVoltage
        warndlg(sprintf('The burst voltage of %.1f V (High Voltage P2) is above the transducer limit of %.1f V.', ...
            TPC(2).hv, Trans.maxHighVoltage), 'Burst')
        return
    end
    if confirm
        answer = questdlg(sprintf(['Acquire a burst: %i frames at %.1f V, %i frames at %.1f V, %i frames at %.1f V?\n\n' ...
            'The burst voltage can collapse gas vesicles irreversibly.'], ...
            P.burst_pre_frames, TPC(1).hv, P.burst_collapse_frames, TPC(2).hv, P.burst_post_frames, TPC(1).hv), ...
            'Burst', 'Burst', 'Cancel', 'Cancel');
        if ~strcmp(answer, 'Burst'), return, end
    end

    B = struct();
    B.active = true; % until xw_burst_finish
    B.plan = plan;
    B.num_frames = plan.num_frames;
    B.image_count = 0; % images saved by xw_burst_save_image
    B.voltage_imaging = TPC(1).hv;
    B.voltage_burst = TPC(2).hv;
    B.voltage = B.voltage_imaging * (plan.profile == 1) + B.voltage_burst * (plan.profile == 2); % [V] per frame
    B.folder = fullfile(P.record_path, [datestr(now, 'yyyymmdd_HHMMSS') '_burst']); %#ok<TNOW1,DATST>
    B.images = []; % [depth, rays, frames], set by the first image
    B.x_axis = P.burst_x_axis; % [mm]
    B.z_axis = P.burst_z_axis;
    B.t_start = datetime('now');
    mkdir(B.folder);
    xw_sequence_save_acquisition_parameters(fullfile(B.folder, 'acq_parameters.mat'));
    assignin('base', 'XWBurst', B);
    xw_burst_update_button();

    fprintf('Burst: %i frames at %.1f V, %i at %.1f V, %i at %.1f V (nominal frame rate %.0f Hz), to %s\n', ...
        P.burst_pre_frames, B.voltage_imaging, P.burst_collapse_frames, B.voltage_burst, P.burst_post_frames, B.voltage_imaging, ...
        1 / P.burst_frame_period, B.folder);
    xw_set_start_event(evalin('base', 'EN.Burst'));
end
