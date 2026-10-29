function xw_rca_burst_finish(status, restart)
    % xw_rca_burst_finish(status, restart)
    %   End of a burst of the RCA, the counterpart of xw_burst_finish: saves
    %   burst.mat (the reconstructed volumes of all burst frames [depth, second
    %   axis, first axis, frames] and the voltages), a plot of the mean level per
    %   frame and the burst analysis figure in the burst folder, and, if restart
    %   (default true), returns the sequence to live imaging. Called without
    %   arguments by the last event of the burst events; xw_sequence_start calls
    %   it with status 'aborted' and restart false when the sequence is restarted
    %   during a burst.
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
    xw_rca_burst_rf('clear'); % free the raw RF

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
    R.images = B.images(:, :, :, 1:n); % reconstructed envelope [depth, second axis, first axis, frames]
    R.z_axis = B.z_axis_burst; % [mm]
    R.axis_first = B.axis_first; % [mm] elements that transmit first
    R.axis_second = B.axis_second;
    R.frame_period = P.burst_frame_period; % nominal time between frames [s]
    R.time = (0:n - 1) * P.burst_frame_period; % nominal time of each frame [s]
    R.host_time = B.capture_host_time(1:n) - B.capture_host_time(1); % host time at which each frame was copied [s]
    R.voltage = B.voltage(1:n); % transmit voltage of each frame [V]
    R.tpc_profile = B.plan.profile(1:n); % 1 = imaging voltage, 2 = burst voltage
    R.num_pre_frames = P.burst_pre_frames;
    R.num_collapse_frames = P.burst_collapse_frames;
    R.num_post_frames = P.burst_post_frames;
    R.t_start = B.t_start;
    R.t_end = datetime('now');
    sz = size(R.images);
    flat = reshape(R.images, sz(1), [], n); % the difference is linear: any shape of the frames will do
    D = xw_burst_difference(flat, P.burst_pre_frames, P.burst_collapse_frames);
    for name = {'image', 'reference_image', 'difference'}
        if ~isempty(D.(name{1})), D.(name{1}) = reshape(D.(name{1}), sz(1:3)); end
    end
    R.analysis = D; % first frame at the burst voltage minus the mean of the next ones
    save(fullfile(B.folder, 'burst.mat'), '-struct', 'R', '-v7.3', '-nocompression');
    fprintf('Burst %s: %i frames saved in %s\n', status, n, B.folder);

    % mean level per frame
    trace = squeeze(mean(R.images, [1 2 3]));
    f = figure('Name', 'xAM burst', 'NumberTitle', 'off', 'Color', 'w', 'Visible', 'off');
    ax = axes(f);
    hold(ax, 'on');
    plot(ax, 1:n, trace, '-o', 'LineWidth', 1.5, 'DisplayName', 'mean volume');
    collapse = find(R.tpc_profile == 2);
    if ~isempty(collapse)
        % patch rather than xregion, which needs MATLAB R2023a or later
        yl = ylim(ax);
        shade = patch(ax, [collapse(1) - 0.5, collapse(end) + 0.5, collapse(end) + 0.5, collapse(1) - 0.5], ...
            yl([1 1 2 2]), [1 0.9 0.8], 'EdgeColor', 'none', 'DisplayName', 'burst voltage');
        uistack(shade, 'bottom');
    end
    xlabel(ax, 'Frame');
    ylabel(ax, {'Mean reconstructed envelope', 'linear [a.u.]'});
    title(ax, sprintf('Burst (%s)', status), 'Interpreter', 'none');
    legend(ax, 'Location', 'best');
    grid(ax, 'on');
    exportgraphics(f, fullfile(B.folder, 'burst.png'), 'Resolution', 150);
    close(f);

    plot_analysis(B, R, D);
end

function plot_analysis(B, R, D)
    % Figure of the burst analysis, as for the linear array: the first frame at the burst voltage,
    % the mean of the subsequent frames at the same voltage and their difference (linear, signed;
    % red: in the first frame and gone later), here as two slices of the volume: depth against the
    % first axis (top) and against the second axis (bottom), at the position of the largest difference.
    if isempty(D.difference)
        fprintf('Burst analysis skipped: frame %i and the frames after it at the burst voltage are not available\n', D.frame);
        return
    end
    UISTATES = evalin_if_exist('base', 'UISTATES', struct('dr_bmode', 40));
    DR = UISTATES.dr_bmode;
    ref_str = sprintf('frames %i-%i', D.reference(1), D.reference(end));
    peak = max(D.image(:));
    to_db = @(im) 20 * log10(max(im, eps(peak)) / peak); % relative to the maximum of the frame
    energy = abs(D.difference) .^ 2;
    [~, i2] = max(squeeze(sum(energy, [1 3]))); % second axis position
    [~, i3] = max(squeeze(sum(energy, [1 2]))); % first axis position
    lim = max(abs(D.difference(:)));

    f = figure('Name', 'xAM burst analysis', 'NumberTitle', 'off', 'Color', 'w', 'Position', [60 100 1400 800]);
    tl = tiledlayout(f, 2, 3, 'TileSpacing', 'compact');
    for row = 1:2
        if row == 1
            sl = @(v) squeeze(v(:, i2, :)); ax_h = R.axis_first; lab = sprintf('first axis [mm] (second axis at %.1f mm)', R.axis_second(i2));
        else
            sl = @(v) squeeze(v(:, :, i3)); ax_h = R.axis_second; lab = sprintf('second axis [mm] (first axis at %.1f mm)', R.axis_first(i3));
        end
        panels = {D.image, D.reference_image};
        titles = {sprintf('Frame %i (%.1f V), dB', D.frame, R.voltage(D.frame)), ...
            sprintf('Mean of %s (%.1f V), dB', ref_str, mean(R.voltage(D.reference)))};
        for k = 1:2
            ax = nexttile(tl);
            imagesc(ax, ax_h, R.z_axis, to_db(sl(panels{k})));
            caxis(ax, [-DR 0]); colormap(ax, 'hot'); colorbar(ax); daspect(ax, [1 1 1]);
            xlabel(ax, lab); ylabel(ax, 'Depth [mm]'); title(ax, titles{k});
        end
        ax = nexttile(tl);
        imagesc(ax, ax_h, R.z_axis, sl(D.difference));
        caxis(ax, [-lim lim]); colormap(ax, diverging_map());
        cb = colorbar(ax); cb.Label.String = 'envelope [a.u.], linear';
        daspect(ax, [1 1 1]); xlabel(ax, lab); ylabel(ax, 'Depth [mm]');
        title(ax, sprintf('Frame %i minus mean of %s', D.frame, ref_str));
    end
    title(tl, sprintf('Burst analysis (%s). Left: dB relative to the maximum of frame %i. Right: difference of the linear volumes', R.status, D.frame), 'Interpreter', 'none');
    exportgraphics(f, fullfile(B.folder, 'burst_analysis.png'), 'Resolution', 150);
    savefig(f, fullfile(B.folder, 'burst_analysis.fig'));
end

function map = diverging_map()
    % blue - white - red, 256 levels
    t = linspace(0, 1, 256)';
    map = [min(2 * t, 1), 1 - abs(2 * t - 1), min(2 * (1 - t), 1)];
end
