% RECONSTRUCT_RF  Reconstruct saved RF data offline, as in the live view.
%
% Example script: point it at saved RF data and it reconstructs every frame
% with the same code as the live view (xw_reconstruct_setup and
% xw_reconstruct_frame), log-compresses the images as the live display does,
% and shows the image stack. Use it as a starting point for your own
% processing; the results stay in the workspace:
%
%   images     complex IQ images per mode (PW = B-mode, xAM), [depth, rays, frames]
%   images_dB  log-compressed images as displayed, [depth, rays, frames]
%   x_mm, z_mm image axes [mm]
%   time_tags  hardware time tag per frame [s] (0 in simulation)
%
% Works with
%   - an RF recording folder: Record with Save mode 'Raw RF', or one voltage
%     folder (pass1_02.00V, ...) of a sweep run with --sweep-save rf;
%   - an RF snapshot: the .mat file from Save Data with Save mode 'Raw RF'
%     (its frames are the 4 frames of the receive buffer, not in time order).
%
% Set data_path below, or set it in the workspace before running the script:
%   data_path = 'data/20261013_151911_rf'; run('examples/reconstruct_rf.m')

%% Settings
if ~exist('data_path', 'var') || isempty(data_path)
    data_path = ''; % RF recording folder or RF snapshot .mat; '' = choose in a dialog
end
frames = [];           % frames to reconstruct, [] = all
beamformer = 'auto';   % 'auto' (as the live view: GPU if available), 'gpu' or 'cpu'
persistence = 'saved'; % 'saved' = as the live view when the data was saved, or 0.1..1 (1 = none)
play_fps = 10;         % frames per second when showing the stack, 0 = only show the first frame

%% Paths
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(repo_root, 'dependencies')));

%% Choose the data
if isempty(data_path)
    data_path = uigetdir(fullfile(repo_root, 'data'), 'RF recording folder (Cancel to choose a snapshot .mat)');
    if isequal(data_path, 0)
        [file, folder] = uigetfile(fullfile(repo_root, 'data', '*.mat'), 'RF snapshot');
        if isequal(file, 0), return; end
        data_path = fullfile(folder, file);
    end
end

% relative paths: run() changes to this script's folder, so also look in the repository
if ~isfolder(data_path) && ~isfile(data_path) && (isfolder(fullfile(repo_root, data_path)) || isfile(fullfile(repo_root, data_path)))
    data_path = fullfile(repo_root, data_path);
end
assert(isfolder(data_path) || isfile(data_path), 'Data not found: %s', data_path);

%% Load the sequence parameters, and a function that loads one RF frame
if isfolder(data_path) % RF recording: one file per frame, loaded when needed
    acq = load(fullfile(data_path, 'acq_parameters.mat'));
    info = load(fullfile(data_path, 'recording_info.mat'));
    assert(strcmp(info.mode, 'rf'), ['%s is an image recording: its frames (frame_#####.mat) ' ...
        'already hold the reconstructed images (BFData).'], data_path);
    n_available = info.num_frames;
    load_frame = @(k) xw_load_rf_recording(data_path, k);
else % RF snapshot: all frames are in the file
    acq = load(data_path, 'P', 'Receive', 'Trans', 'TW', 'UISTATES', 'RcvData');
    assert(isfield(acq, 'RcvData'), '%s has no RcvData: save it with Save mode ''Raw RF''.', data_path);
    n_available = size(acq.RcvData{1}, 3);
    load_frame = @(k) acq.RcvData{1}(:, :, k);
end
if isempty(frames), frames = 1:n_available; end
fprintf('Reconstructing %i frame(s) from %s\n', numel(frames), data_path);

%% Set up the reconstruction (same as the live view)
R = xw_reconstruct_setup(acq.P, acq.Receive, acq.Trans, acq.TW, beamformer);
x_mm = R.P.x_axis * 1e3;
z_mm = R.P.z_axis * 1e3;

if strcmp(persistence, 'saved')
    persistence = 1;
    if isfield(acq, 'UISTATES') && isfield(acq.UISTATES, 'persistence')
        persistence = acq.UISTATES.persistence;
    end
end

%% Reconstruct frame by frame (only one RF frame in memory at a time)
n_frames = numel(frames);
images = struct();
for mode = R.modes
    images.(mode{1}) = complex(zeros(numel(z_mm), numel(x_mm), n_frames, 'single'));
end
time_tags = zeros(1, n_frames);
for k = 1:n_frames
    BF = xw_reconstruct_frame(R, load_frame(frames(k)));
    for mode = R.modes
        img = BF.(mode{1});
        if k > 1 && persistence < 1 % blend with the previous frame, as the live view
            img = persistence * img + (1 - persistence) * images.(mode{1})(:, :, k - 1);
        end
        images.(mode{1})(:, :, k) = img;
    end
    time_tags(k) = BF.TimeTag;
    fprintf('  frame %i/%i\n', k, n_frames);
end

%% Log-compress as the live display: dB relative to the maximum of each frame
images_dB = struct();
for mode = R.modes
    images_dB.(mode{1}) = zeros(size(images.(mode{1})), 'single');
    for k = 1:n_frames
        images_dB.(mode{1})(:, :, k) = flogc(abs(images.(mode{1})(:, :, k)));
    end
end

% dynamic range as set in the live view when the data was saved
dynamic_range = struct('PW', 40, 'xBmode', 40, 'xAM', 20);
if isfield(acq, 'UISTATES')
    dynamic_range.PW = acq.UISTATES.dr_bmode;
    dynamic_range.xBmode = acq.UISTATES.dr_bmode;
    dynamic_range.xAM = acq.UISTATES.dr_xam;
end

%% Show the image stack
titles = struct('PW', 'B-mode', 'xBmode', 'xB-mode', 'xAM', 'xAM');
fig = figure('Name', 'Reconstructed RF data', 'NumberTitle', 'off', 'Color', 'w');
layout = tiledlayout(fig, 1, numel(R.modes), 'TileSpacing', 'compact');
handles = gobjects(1, numel(R.modes));
for m = 1:numel(R.modes)
    mode = R.modes{m};
    ax = nexttile(layout);
    handles(m) = imshow(images_dB.(mode)(:, :, 1), [-dynamic_range.(mode) 0], ...
        'XData', x_mm([1 end]), 'YData', z_mm([1 end]), 'Parent', ax);
    axis(ax, 'on');
    colormap(ax, bone);
    colorbar(ax);
    xlabel(ax, 'Lateral position [mm]');
    ylabel(ax, 'Depth [mm]');
    title(ax, titles.(mode));
end
for k = 1:n_frames * (play_fps > 0)
    for m = 1:numel(R.modes)
        handles(m).CData = images_dB.(R.modes{m})(:, :, k);
    end
    title(layout, sprintf('Frame %i (%i of %i)', frames(k), k, n_frames));
    drawnow;
    pause(1 / play_fps);
end
