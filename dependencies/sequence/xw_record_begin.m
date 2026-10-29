function ok = xw_record_begin(mode, num_frames, folder)
    % ok = xw_record_begin(mode, num_frames, folder)
    %   Start recording the next num_frames frames into folder (created here),
    %   as 'rf' or 'images'. Used by the Record button (xw_record_start) and
    %   by the voltage sweep. Returns false if the recording could not start.
    %   See xw_record_start for the file formats.
    ok = false;
    P = evalin('base', 'P');
    Resource = evalin('base', 'Resource');

    % estimate required disk space, and refuse if it does not fit
    switch mode
        case 'rf'
            bytes_per_frame = Resource.RcvBuffer(1).rowsPerFrame * Resource.RcvBuffer(1).colsPerFrame * 2; % int16
        case 'images'
            if isfield(P, 'image_bytes_per_frame') % other image size, e.g. xAM_imaging_RCA.m
                bytes_per_frame = P.image_bytes_per_frame;
            else
                bytes_per_frame = numel(P.ray_positions) * 2 * 8 * ...
                numel(P.image_start_depth_mm:P.scale_wvl2mm / 2:P.image_end_depth_mm) * numel(P.beamform_image_modes); % complex single, raw + persisted
            end
    end
    bytes_needed = bytes_per_frame * num_frames;
    if ~isfolder(folder); mkdir(folder); end
    bytes_free = java.io.File(folder).getUsableSpace();
    if bytes_needed > 0.95 * bytes_free
        errordlg(sprintf('Not enough disk space in %s: need %.1f GB, %.1f GB free.', ...
            folder, bytes_needed / 1e9, bytes_free / 1e9), 'Record')
        return
    end

    xw_sequence_save_acquisition_parameters(fullfile(folder, 'acq_parameters.mat'));

    XWRecord = struct();
    XWRecord.active = true;
    XWRecord.mode = mode;
    XWRecord.num_frames = num_frames;
    XWRecord.frame_count = 0;
    XWRecord.folder = folder;
    XWRecord.time_tags = NaN(1, XWRecord.num_frames); % hardware time tags [s]
    XWRecord.host_times = NaN(1, XWRecord.num_frames); % host clock at time of saving [posix s]
    XWRecord.pending = parallel.FevalFuture.empty; % background writes still running
    if strcmp(XWRecord.mode, 'rf')
        XWRecord.frame_files = 'frame_%05i.bin';
        XWRecord.frame_size = [Resource.RcvBuffer(1).rowsPerFrame, Resource.RcvBuffer(1).colsPerFrame];
        [~, ~, endian] = computer;
        XWRecord.byte_order = 'ieee-le';
        if endian == 'B'; XWRecord.byte_order = 'ieee-be'; end
        % With waitForProcessing, the hardware can refill the receive-buffer
        % frame of frame k once frame k + num_rf_frames - 1 is being processed.
        % Allowing num_rf_frames - 2 writes to run on guarantees each write has
        % finished before then, even if RFData shares memory with the buffer.
        XWRecord.max_pending = max(1, P.num_rf_frames - 2);
        % start the background threads now (~0.6 s the first time), not on the first frame
        wait(parfeval(backgroundPool, @() [], 0));
    end
    xw_record_save_info(XWRecord);
    assignin('base', 'XWRecord', XWRecord);
    xw_burst_update_button();

    fprintf('Recording %i frames (%s, ~%.1f GB) to %s\n', XWRecord.num_frames, XWRecord.mode, bytes_needed / 1e9, folder);
    ok = true;
end
