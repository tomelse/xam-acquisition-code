function xw_sweep_frame(BFData)
    % Advance an active voltage sweep by one frame. Called from
    % xw_beamform_run after xw_record_frame, with the beamformed frame before
    % persistence. Each step: settle (frames discarded), then record and
    % measure S.frames frames, then move to the next voltage.

    if ~evalin('base', 'exist(''XWSweep'', ''var'') && XWSweep.active')
        return
    end
    S = evalin('base', 'XWSweep');

    try
        p = S.steps(S.step, 1);
        vi = S.steps(S.step, 2);
        switch S.phase
            case 'settle'
                S.phase_frames = S.phase_frames + 1;
                if S.phase_frames >= S.settle_frames && toc(S.t_set) >= S.settle_needed_s
                    % record the next S.frames frames (recording starts with the next frame)
                    sub = fullfile(S.folder, sprintf('pass%i_%05.2fV', p, S.hv_set(p, vi)));
                    if ~xw_record_begin(S.mode, S.frames, sub)
                        xw_sweep_finish(S, 'recording could not start');
                        return
                    end
                    S.phase = 'record';
                    S.phase_frames = 0;
                end

            case 'record'
                % this frame is the one just recorded by xw_record_frame.
                % Measure the mean envelope (|IQ|, linear, before log
                % compression) over the region where the plane waves cross.
                if isempty(S.roi)
                    P = evalin('base', 'P');
                    if isfield(P, 'crossing_roi_function') % other geometry, e.g. xAM_imaging_RCA.m
                        S.roi = feval(P.crossing_roi_function, P);
                    else
                        S.roi = xw_crossing_roi(P);
                    end
                end
                k = S.phase_frames + 1;
                S.mean_xam(p, vi, k) = mean(abs(BFData.xAM(S.roi)));
                if isfield(BFData, 'PW')
                    S.mean_bmode(p, vi, k) = mean(abs(BFData.PW(S.roi)));
                end
                S.phase_frames = k;
                if k >= S.frames
                    S.step = S.step + 1;
                    if S.step > size(S.steps, 1)
                        xw_sweep_finish(S, 'complete');
                        return
                    end
                    S = xw_sweep_next_step(S);
                end
        end
        assignin('base', 'XWSweep', S);
    catch e
        fprintf(2, 'Sweep stopped: %s\n', e.message);
        xw_sweep_finish(S, ['error: ' e.message]);
    end
end
