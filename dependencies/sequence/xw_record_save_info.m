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
        info.rf_file = XWRecord.rf_file;
        info.frame_size = XWRecord.frame_size; % [rows, channels] per frame
        info.data_class = 'int16';
        info.byte_order = XWRecord.byte_order;
        info.layout = '[rows, channels, frames], column-major (MATLAB order), frames appended';
    end
    save(fullfile(XWRecord.folder, 'recording_info.mat'), '-struct', 'info', '-v7');
end
