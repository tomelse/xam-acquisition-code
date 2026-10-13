function xw_record_finish(XWRecord)
    % Close a recording: close the raw RF file, store frame timing in
    % recording_info.mat, report the achieved frame rate and mark the
    % recording inactive.

    P = evalin('base', 'P');
    if XWRecord.fid >= 0
        fclose(XWRecord.fid);
        XWRecord.fid = -1;
    end
    info = xw_record_save_info(XWRecord);

    % frame timing from the hardware time tags if enabled, else from the host clock
    dt = diff(info.time_tags);
    clock_name = 'time tags';
    if isempty(dt) || any(~isfinite(dt) | dt <= 0)
        dt = diff(info.host_times);
        clock_name = 'host clock';
    end
    fprintf('Recording done: %i frames in %s\n', info.num_frames, XWRecord.folder);
    if ~isempty(dt)
        n_late = nnz(dt > 1.5 / P.fps);
        fprintf('  mean frame rate %.2f Hz (nominal %.2f Hz, %s), %i frame intervals > 1.5x nominal\n', ...
            1 / mean(dt), P.fps, clock_name, n_late);
    end

    XWRecord.active = false;
    assignin('base', 'XWRecord', XWRecord);
end
