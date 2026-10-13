function [RF, info] = xw_load_rf_recording(folder, frames)
    % [RF, info] = xw_load_rf_recording(folder, frames)
    %   Load frames from a raw RF recording made with the 'Record' button.
    %
    %   folder  : recording folder (contains frame_00001.bin, ... and
    %             recording_info.mat)
    %   frames  : frame indices to load (default: all complete frames)
    %   RF      : int16 [rows, channels, numel(frames)], same layout as RcvData
    %   info    : contents of recording_info.mat (time tags, frame size, ...)
    %
    %   The sequence parameters (P, Receive, TX, ...) are in acq_parameters.mat
    %   in the same folder. Recordings with all frames in a single rf_data.bin
    %   (older format) are read as well.
    if nargin < 2; frames = []; end
    info = load(fullfile(folder, 'recording_info.mat'));
    bytes_per_frame = prod(info.frame_size) * 2;

    if isfield(info, 'rf_file') % older format: frames appended to one file
        fn = fullfile(folder, info.rf_file);
        d = dir(fn);
        num_frames = floor(d.bytes / bytes_per_frame); % complete frames only
        if isempty(frames); frames = 1:num_frames; end
        assert(all(frames >= 1 & frames <= num_frames), 'Frames must be in 1..%i', num_frames);
        m = memmapfile(fn, 'Format', {info.data_class, info.frame_size, 'RF'}, 'Repeat', num_frames);
        RF = zeros([info.frame_size, numel(frames)], info.data_class);
        for k = 1:numel(frames)
            RF(:, :, k) = m.Data(frames(k)).RF;
        end
        return
    end

    % one file per frame; use the complete frame files present (also works if
    % a recording was interrupted or a frame failed to write)
    frame_file = @(k) fullfile(folder, sprintf(info.frame_files, k));
    d = dir(fullfile(folder, regexprep(info.frame_files, '%\d*i', '*')));
    d = d([d.bytes] == bytes_per_frame);
    complete = sort(cellfun(@(n) sscanf(n, info.frame_files), {d.name}));
    if isempty(frames)
        frames = complete;
    end
    missing = setdiff(frames, complete);
    assert(isempty(missing), 'Frame(s) %s are missing or incomplete; complete frames: %s', ...
        mat2str(missing), mat2str(complete));

    % explicit byte order only when it differs from this machine (it slows fread)
    [~, ~, endian] = computer;
    machine_fmt = 'n';
    if ~strcmp(info.byte_order, ['ieee-' lower(endian) 'e']); machine_fmt = info.byte_order; end

    RF = zeros([info.frame_size, numel(frames)], info.data_class);
    for k = 1:numel(frames)
        fid = fopen(frame_file(frames(k)), 'r', machine_fmt);
        RF(:, :, k) = fread(fid, info.frame_size, ['*' info.data_class]);
        fclose(fid);
    end
end
