function xw_sweep_finish(S, reason)
    % End a voltage sweep: stop any recording of the current step, restore the
    % voltage from before the sweep, save sweep_results.mat and plot the mean
    % xAM signal against voltage for each pass.
    S.active = false;
    assignin('base', 'XWSweep', S);

    XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
    if XWRecord.active
        xw_record_stop(XWRecord);
    end
    try
        xw_sweep_set_voltage(S.hv_initial);
    catch e
        fprintf(2, 'Sweep: could not restore %.2f V: %s\n', S.hv_initial, e.message);
    end

    % results: mean and standard deviation over the frames of each step
    R = struct();
    R.status = reason;
    R.voltages_requested = S.voltages;
    R.hv_set = S.hv_set; % [passes, voltages]
    % mean xAM / B-mode envelope (|IQ|, linear, before log compression) over R.roi
    R.mean_xam_frames = S.mean_xam; % [passes, voltages, frames]
    R.mean_bmode_frames = S.mean_bmode;
    R.mean_xam = mean(S.mean_xam, 3, 'omitnan');
    R.std_xam = std(S.mean_xam, 0, 3, 'omitnan');
    R.mean_bmode = mean(S.mean_bmode, 3, 'omitnan');
    R.frames_per_voltage = S.frames;
    R.settle_frames = S.settle_frames;
    R.settle_s = [S.settle_s, S.settle_s_down];
    R.save_mode = S.mode;
    R.roi = S.roi;
    R.roi_description = 'pixels above the per-ray crossing depth of the two plane waves';
    R.t_start = S.t_start;
    R.t_end = datetime('now');
    save(fullfile(S.folder, 'sweep_results.mat'), '-struct', 'R', '-v7');

    fprintf('Sweep %s: results in %s\n', reason, S.folder);
    if all(isnan(R.mean_xam(:)))
        return
    end

    % plot
    f = figure('Name', 'xAM voltage sweep', 'NumberTitle', 'off', 'Color', 'w');
    tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
    ax = nexttile;
    hold(ax, 'on');
    for p = 1:S.passes
        errorbar(ax, R.hv_set(p, :), R.mean_xam(p, :), R.std_xam(p, :), '-o', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('Pass %i', p));
    end
    ylabel(ax, {'Mean xAM envelope', '|IQ|, linear [a.u.]'});
    title(ax, sprintf('xAM voltage sweep, %i frames per voltage (%s)', S.frames, reason), 'Interpreter', 'none');
    legend(ax, 'Location', 'northwest');
    grid(ax, 'on');

    % B-mode should scale roughly with voltage: checks that each voltage was applied
    ax2 = nexttile;
    hold(ax2, 'on');
    for p = 1:S.passes
        plot(ax2, R.hv_set(p, :), R.mean_bmode(p, :), '-o', 'LineWidth', 1, 'DisplayName', sprintf('Pass %i', p));
    end
    xlabel(ax2, 'Transmit voltage [V]');
    ylabel(ax2, {'Mean B-mode envelope', '|IQ|, linear [a.u.]'});
    grid(ax2, 'on');
    linkaxes([ax, ax2], 'x');

    exportgraphics(f, fullfile(S.folder, 'sweep_results.png'), 'Resolution', 150);
    savefig(f, fullfile(S.folder, 'sweep_results.fig'));
end
