function xw_record_start()
    % Callback of the 'Record' button. Starts recording the next
    % UISTATES.record_num_frames frames to disk, either as raw RF data or as
    % beamformed images, depending on UISTATES.save_mode. Pressing the button
    % while a recording is running stops the recording early.
    %
    % Frames are written by xw_record_frame, which is called from
    % xw_beamform_run for every acquired frame:
    %   - RF:     one raw binary file per frame, frame_00001.bin, ... (int16,
    %             native byte order, [rows, channels] in column-major order),
    %             written on background threads. Read them back with
    %             xw_load_rf_recording.
    %   - images: one -v7.3 file per frame, frame_00001.mat, ...
    % recording_info.mat describes the recording; it is written at the start,
    % so the raw file stays readable if a recording is interrupted.

    XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
    XWSweep = evalin_if_exist('base', 'XWSweep', struct('active', false));
    if XWSweep.active
        warndlg('A voltage sweep is running. Press Voltage sweep to stop it first.', 'Record')
        return
    end
    if XWRecord.active
        fprintf('Recording stopped by user after %i of %i frames\n', XWRecord.frame_count, XWRecord.num_frames);
        xw_record_stop(XWRecord);
        return
    end

    if evalin_if_exist('base', 'freeze', 0)
        warndlg('Unfreeze the sequence before starting a recording.', 'Record')
        return
    end

    P = evalin('base', 'P');
    UISTATES = evalin('base', 'UISTATES');
    folder = fullfile(P.record_path, [datestr(now, 'yyyymmdd_HHMMSS') '_' UISTATES.save_mode]); %#ok<TNOW1,DATST>
    xw_record_begin(UISTATES.save_mode, UISTATES.record_num_frames, folder);
end
