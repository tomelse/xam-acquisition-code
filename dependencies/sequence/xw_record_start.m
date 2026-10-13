function xw_record_start()
    % Callback of the 'Record' button. Starts recording the next
    % UISTATES.record_num_frames frames to disk, either as raw RF data or as
    % beamformed images, depending on UISTATES.save_mode. Pressing the button
    % while a recording is running stops the recording early.
    %
    % Frames are written by xw_record_frame, which is called from
    % xw_beamform_run for every acquired frame:
    %   - RF:     appended to one raw binary file, rf_data.bin (int16, native
    %             byte order, [rows, channels, frames] in column-major order).
    %             Read it back with xw_load_rf_recording.
    %   - images: one -v7.3 file per frame, frame_00001.mat, ...
    % recording_info.mat describes the recording; it is written at the start,
    % so the raw file stays readable if a recording is interrupted.

    XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
    if XWRecord.active
        fprintf('Recording stopped by user after %i of %i frames\n', XWRecord.frame_count, XWRecord.num_frames);
        xw_record_finish(XWRecord);
        return
    end

    if evalin_if_exist('base', 'freeze', 0)
        warndlg('Unfreeze the sequence before starting a recording.', 'Record')
        return
    end

    P = evalin('base', 'P');
    UISTATES = evalin('base', 'UISTATES');
    Resource = evalin('base', 'Resource');

    % estimate required disk space, and refuse if it does not fit
    switch UISTATES.save_mode
        case 'rf'
            bytes_per_frame = Resource.RcvBuffer(1).rowsPerFrame * Resource.RcvBuffer(1).colsPerFrame * 2; % int16
        case 'images'
            bytes_per_frame = numel(P.ray_positions) * 2 * 8 * ...
                numel(P.image_start_depth_mm:P.scale_wvl2mm / 2:P.image_end_depth_mm) * numel(P.beamform_image_modes); % complex single, raw + persisted
    end
    bytes_needed = bytes_per_frame * UISTATES.record_num_frames;
    if ~isfolder(P.record_path); mkdir(P.record_path); end
    bytes_free = java.io.File(P.record_path).getUsableSpace();
    if bytes_needed > 0.95 * bytes_free
        errordlg(sprintf('Not enough disk space in %s: need %.1f GB, %.1f GB free.', ...
            P.record_path, bytes_needed / 1e9, bytes_free / 1e9), 'Record')
        return
    end

    folder = fullfile(P.record_path, [datestr(now, 'yyyymmdd_HHMMSS') '_' UISTATES.save_mode]); %#ok<TNOW1,DATST>
    mkdir(folder);
    xw_sequence_save_acquisition_parameters(fullfile(folder, 'acq_parameters.mat'));

    XWRecord = struct();
    XWRecord.active = true;
    XWRecord.mode = UISTATES.save_mode;
    XWRecord.num_frames = UISTATES.record_num_frames;
    XWRecord.frame_count = 0;
    XWRecord.folder = folder;
    XWRecord.time_tags = NaN(1, XWRecord.num_frames); % hardware time tags [s]
    XWRecord.host_times = NaN(1, XWRecord.num_frames); % host clock at time of saving [posix s]
    XWRecord.fid = -1;
    if strcmp(XWRecord.mode, 'rf')
        XWRecord.rf_file = 'rf_data.bin';
        XWRecord.frame_size = [Resource.RcvBuffer(1).rowsPerFrame, Resource.RcvBuffer(1).colsPerFrame];
        % native byte order: an explicit 'ieee-le' makes fwrite ~3.5x slower,
        % even on little-endian machines
        [~, ~, endian] = computer;
        XWRecord.byte_order = 'ieee-le';
        if endian == 'B'; XWRecord.byte_order = 'ieee-be'; end
        XWRecord.fid = fopen(fullfile(folder, XWRecord.rf_file), 'w');
        if XWRecord.fid < 0
            errordlg(sprintf('Could not open %s for writing.', fullfile(folder, XWRecord.rf_file)), 'Record')
            return
        end
    end
    xw_record_save_info(XWRecord);
    assignin('base', 'XWRecord', XWRecord);

    fprintf('Recording %i frames (%s, ~%.1f GB) to %s\n', XWRecord.num_frames, XWRecord.mode, bytes_needed / 1e9, folder);
end
