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
end
