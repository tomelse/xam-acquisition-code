function xw_record_finish(XWRecord, futures)
    % Called by xw_record_stop once all background writes of a recording have
    % finished: checks the writes, writes the final recording_info.mat and
    % reports the achieved frame rate.

    P = evalin('base', 'P');

    % frames whose background write failed (RF recordings only)
    XWRecord.failed_frames = [];
    for f = reshape(futures, 1, [])
        if ~isempty(f.Error)
            fprintf(2, 'Recording: %s\n', f.Error.message);
        end
    end
    if isfield(XWRecord, 'frame_files')
        ok = arrayfun(@(k) is_complete(XWRecord, k), 1:XWRecord.frame_count);
        XWRecord.failed_frames = find(~ok);
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
    if ~isempty(XWRecord.failed_frames)
        fprintf(2, '  %i frame(s) failed to write: %s\n', numel(XWRecord.failed_frames), mat2str(XWRecord.failed_frames));
    end
    if ~isempty(dt)
        n_late = nnz(dt > 1.5 / P.fps);
        fprintf('  mean frame rate %.2f Hz (nominal %.2f Hz, %s), %i frame intervals > 1.5x nominal\n', ...
            1 / mean(dt), P.fps, clock_name, n_late);
    end
end

function ok = is_complete(XWRecord, k)
    fn = fullfile(XWRecord.folder, sprintf(XWRecord.frame_files, k));
    ok = isfile(fn);
    if ok
        d = dir(fn);
        ok = d.bytes == prod(XWRecord.frame_size) * 2;
    end
end
