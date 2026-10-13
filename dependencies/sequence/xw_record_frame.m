function xw_record_frame(RFData, BFData)
    % Write the current frame to disk if a recording is active. Called from
    % xw_beamform_run with the RF data of the frame and the beamformed data
    % before persistence is applied.
    %
    % With Resource.Parameters.waitForProcessing = 1, the hardware does not
    % transfer a new frame before the previous one has been picked up for
    % processing, so no frames are skipped. If saving is slower than the
    % acquisition, the frame rate drops instead; check the time tags in
    % recording_info.mat.
    %
    % RF frames are written on background threads, so the write overlaps with
    % processing of the next frames. At most XWRecord.max_pending writes are
    % left running when this function returns (see xw_record_start): RFData
    % may share memory with the receive buffer, so each write must finish
    % before the hardware can reuse that buffer frame.

    if ~evalin('base', 'exist(''XWRecord'', ''var'') && XWRecord.active')
        return
    end
    XWRecord = evalin('base', 'XWRecord');

    k = XWRecord.frame_count + 1;
    TimeTag = BFData.TimeTag;
    switch XWRecord.mode
        case 'rf'
            if ~isequal(size(RFData), XWRecord.frame_size)
                fprintf(2, 'Recording stopped: RF frame size %s does not match recording frame size %s\n', ...
                    mat2str(size(RFData)), mat2str(XWRecord.frame_size));
                xw_record_stop(XWRecord);
                return
            end

            % drop finished writes, and stop if one failed
            pending = XWRecord.pending;
            finished = arrayfun(@(f) strcmp(f.State, 'finished'), pending);
            failed = pending(finished & arrayfun(@(f) ~isempty(f.Error), pending));
            if ~isempty(failed)
                fprintf(2, 'Recording stopped after %i frames: %s\n', XWRecord.frame_count, failed(1).Error.message);
                xw_record_stop(XWRecord);
                return
            end
            XWRecord.pending = pending(~finished);

            % keep at most max_pending writes running (waits if the disk is too slow)
            while numel(XWRecord.pending) >= XWRecord.max_pending
                wait(XWRecord.pending(1));
                XWRecord.pending(1) = [];
            end

            fn = fullfile(XWRecord.folder, sprintf(XWRecord.frame_files, k));
            XWRecord.pending(end + 1) = parfeval(backgroundPool, @xw_record_write_frame, 0, fn, RFData);
        case 'images'
            frame_index = k; %#ok<NASGU> saved to file
            fn = fullfile(XWRecord.folder, sprintf('frame_%05i.mat', k));
            save(fn, 'BFData', 'TimeTag', 'frame_index', '-v7.3', '-nocompression');
    end

    XWRecord.frame_count = k;
    XWRecord.time_tags(k) = TimeTag;
    XWRecord.host_times(k) = posixtime(datetime('now'));
    assignin('base', 'XWRecord', XWRecord);

    if k >= XWRecord.num_frames
        xw_record_stop(XWRecord);
    end
end
