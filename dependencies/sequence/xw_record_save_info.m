function info = xw_record_save_info(XWRecord)
    % Write recording_info.mat for a recording: frame count and timing, and for
    % RF recordings the layout of the raw binary file.
    P = evalin('base', 'P');
    n = XWRecord.frame_count;

    info.mode = XWRecord.mode;
    info.num_frames_requested = XWRecord.num_frames;
    info.num_frames = n;
    info.time_tags = XWRecord.time_tags(1:n); % hardware time tags [s]
    info.host_times = XWRecord.host_times(1:n); % host clock when frame was saved [posix s]
    info.fps_nominal = P.fps;
    if strcmp(XWRecord.mode, 'rf')
        info.frame_files = XWRecord.frame_files; % sprintf pattern, one file per frame
        info.frame_size = XWRecord.frame_size; % [rows, channels] per frame
        info.data_class = 'int16';
        info.rf_datatype = 'int16'; % 'half': the int16 values are the bit patterns of half (16 bit float) data, see xw_half2single
        if isfield(P, 'rf_datatype'), info.rf_datatype = P.rf_datatype; end
        info.byte_order = XWRecord.byte_order;
        info.layout = 'one file per frame, [rows, channels], column-major (MATLAB order)';
        if isfield(XWRecord, 'failed_frames')
            info.failed_frames = XWRecord.failed_frames; % frames that could not be written
        end
    end
    save(fullfile(XWRecord.folder, 'recording_info.mat'), '-struct', 'info', '-v7');
end
