function xw_burst_finish(status, restart)
    % xw_burst_finish(status, restart)
    %   End of a burst: saves burst.mat (the reconstructed images of all burst
    %   frames and the voltages) and a plot of the mean image level per frame in
    %   the burst folder, and, if restart (default true), returns the sequence to live
    %   imaging. Called without arguments by the last event of the burst
    %   events; xw_sequence_start calls it with status 'aborted' and restart
    %   false when the sequence is restarted during a burst.
    if nargin < 1, status = 'complete'; end
    if nargin < 2, restart = true; end

    if ~evalin('base', 'exist(''XWBurst'', ''var'') && XWBurst.active')
        return
    end
    B = evalin('base', 'XWBurst');
    B.active = false;
    assignin('base', 'XWBurst', B);
    if restart
        xw_set_start_event(evalin('base', 'EN.StartEvent')); % back to live imaging
    end
    xw_burst_update_button();

    try
        save_burst(B, status);
    catch e
        fprintf(2, 'Burst: could not save %s: %s\n', B.folder, e.message);
    end
end

function save_burst(B, status)
    P = evalin('base', 'P');
    n = B.image_count;
    if n == 0
        fprintf('Burst %s: no frames reconstructed, nothing saved\n', status);
        return
    end
    if n < B.num_frames
        status = sprintf('%s, %i of %i frames', status, n, B.num_frames);
    end
    R = struct();
    R.status = status;
    R.images = B.images(:, :, 1:n); % reconstructed intensity [depth, lateral, frames]
    R.x_axis = B.x_axis; % [mm]
    R.z_axis = B.z_axis; % [mm]
    R.frame_period = P.burst_frame_period; % nominal time between frames [s]
    R.time = (0:n - 1) * P.burst_frame_period; % nominal time of each frame [s]
    R.voltage = B.voltage(1:n); % transmit voltage of each frame [V]
    R.tpc_profile = B.plan.profile(1:n); % 1 = imaging voltage, 2 = burst voltage
    R.num_pre_frames = P.burst_pre_frames;
    R.num_collapse_frames = P.burst_collapse_frames;
    R.num_post_frames = P.burst_post_frames;
    R.t_start = B.t_start;
    R.t_end = datetime('now');
    D = xw_burst_difference(R.images, P.burst_pre_frames, P.burst_collapse_frames);
    R.analysis = D; % first frame at the burst voltage minus the mean of the next ones, see plot_analysis
    save(fullfile(B.folder, 'burst.mat'), '-struct', 'R', '-v7.3', '-nocompression');
    fprintf('Burst %s: %i frames saved in %s\n', status, n, B.folder);

    % mean image level per frame
    trace = squeeze(mean(R.images, [1 2]));
    f = figure('Name', 'xAM burst', 'NumberTitle', 'off', 'Color', 'w', 'Visible', 'off');
    ax = axes(f);
    hold(ax, 'on');
    plot(ax, 1:n, trace, '-o', 'LineWidth', 1.5, 'DisplayName', 'mean image');
    collapse = find(R.tpc_profile == 2);
    if ~isempty(collapse)
        xregion(ax, collapse(1) - 0.5, collapse(end) + 0.5, 'FaceColor', [1 0.9 0.8], 'DisplayName', 'burst voltage');
    end
    xlabel(ax, 'Frame');
    ylabel(ax, {'Mean reconstructed intensity', 'linear [a.u.]'});
    title(ax, sprintf('Burst (%s)', status), 'Interpreter', 'none');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');
    exportgraphics(f, fullfile(B.folder, 'burst.png'), 'Resolution', 150);
    close(f);

    plot_analysis(B, R, D);
end

function plot_analysis(B, R, D)
    % Figure of the burst analysis: the first frame at the burst voltage, the mean of the
    % subsequent frames at the same voltage and their difference. The images are subtracted
    % as reconstructed (linear intensity); only the first two panels are log compressed for display.
    % Shown, and saved as burst_analysis.png/.fig.
    if isempty(D.difference)
        fprintf('Burst analysis skipped: frame %i and the frames after it at the burst voltage are not available\n', D.frame);
        return
    end
    UISTATES = evalin_if_exist('base', 'UISTATES', struct('dr_bmode', 40));
    DR = UISTATES.dr_bmode;
    ref_str = sprintf('frames %i-%i', D.reference(1), D.reference(end));
    peak = max(D.image(:));
    to_db = @(im) 20 * log10(max(im, eps(peak)) / peak); % relative to the maximum of the frame

    f = figure('Name', 'xAM burst analysis', 'NumberTitle', 'off', 'Color', 'w', 'Position', [60 200 1400 520]);
    tl = tiledlayout(f, 1, 3, 'TileSpacing', 'compact');
    panels = {D.image, D.reference_image};
    titles = {sprintf('Frame %i (%.1f V), dB', D.frame, R.voltage(D.frame)), ...
        sprintf('Mean of %s (%.1f V), dB', ref_str, mean(R.voltage(D.reference)))};
    for k = 1:2
        ax = nexttile(tl);
        imagesc(ax, R.x_axis, R.z_axis, to_db(panels{k}));
        caxis(ax, [-DR 0]);
        colormap(ax, 'hot');
        colorbar(ax);
        daspect(ax, [1 1 1]);
        xlabel(ax, 'Lateral position [mm]');
        ylabel(ax, 'Depth [mm]');
        title(ax, titles{k});
    end

    % difference: signed, linear, red = present in frame 11 and gone later (what the burst removed)
    ax = nexttile(tl);
    lim = max(abs(D.difference(:)));
    imagesc(ax, R.x_axis, R.z_axis, D.difference);
    caxis(ax, [-lim lim]);
    colormap(ax, diverging_map());
    cb = colorbar(ax);
    cb.Label.String = 'intensity [a.u.], linear';
    daspect(ax, [1 1 1]);
    xlabel(ax, 'Lateral position [mm]');
    ylabel(ax, 'Depth [mm]');
    title(ax, sprintf('Frame %i minus mean of %s', D.frame, ref_str));

    title(tl, sprintf('Burst analysis (%s). Left: dB relative to the maximum of frame %i. Right: difference of the linear images', R.status, D.frame), 'Interpreter', 'none');
    exportgraphics(f, fullfile(B.folder, 'burst_analysis.png'), 'Resolution', 150);
    savefig(f, fullfile(B.folder, 'burst_analysis.fig'));
end

function map = diverging_map()
    % blue - white - red, 256 levels
    t = linspace(0, 1, 256)';
    map = [min(2 * t, 1), 1 - abs(2 * t - 1), min(2 * (1 - t), 1)];
end
