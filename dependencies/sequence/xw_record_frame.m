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

    if ~evalin('base', 'exist(''XWRecord'', ''var'') && XWRecord.active')
        return
    end
    XWRecord = evalin('base', 'XWRecord');

    k = XWRecord.frame_count + 1;
    TimeTag = BFData.TimeTag;
    switch XWRecord.mode
        case 'rf'
            % append to the raw binary file (~25 ms per 188 MB frame on NVMe)
            if ~isequal(size(RFData), XWRecord.frame_size)
                fprintf(2, 'Recording stopped: RF frame size %s does not match recording frame size %s\n', ...
                    mat2str(size(RFData)), mat2str(XWRecord.frame_size));
                xw_record_finish(XWRecord);
                return
            end
            count = fwrite(XWRecord.fid, RFData, 'int16');
            if count ~= numel(RFData)
                fprintf(2, 'Recording stopped: only %i of %i samples written (disk full?)\n', count, numel(RFData));
                xw_record_finish(XWRecord);
                return
            end
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
        xw_record_finish(XWRecord);
    end
end
