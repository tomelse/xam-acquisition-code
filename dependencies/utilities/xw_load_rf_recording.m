function [RF, info] = xw_load_rf_recording(folder, frames)
    % [RF, info] = xw_load_rf_recording(folder, frames)
    %   Load frames from a raw RF recording made with the 'Record' button.
    %
    %   folder  : recording folder (contains rf_data.bin and recording_info.mat)
    %   frames  : frame indices to load (default: all frames)
    %   RF      : int16 [rows, channels, numel(frames)], same layout as RcvData
    %   info    : contents of recording_info.mat (time tags, frame size, ...)
    %
    %   The sequence parameters (P, Receive, TX, ...) are in acq_parameters.mat
    %   in the same folder.
    info = load(fullfile(folder, 'recording_info.mat'));
    fn = fullfile(folder, info.rf_file);

    % number of complete frames in the file (also works for interrupted recordings)
    bytes_per_frame = prod(info.frame_size) * 2;
    d = dir(fn);
    num_frames = floor(d.bytes / bytes_per_frame);
    if nargin < 2 || isempty(frames)
        frames = 1:num_frames;
    end
    assert(all(frames >= 1 & frames <= num_frames), 'Frames must be in 1..%i', num_frames);

    m = memmapfile(fn, 'Format', {info.data_class, info.frame_size, 'RF'}, 'Repeat', num_frames);
    RF = zeros([info.frame_size, numel(frames)], info.data_class);
    for k = 1:numel(frames)
        RF(:, :, k) = m.Data(frames(k)).RF;
    end
end
