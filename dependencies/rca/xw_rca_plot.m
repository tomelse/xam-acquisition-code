function xw_rca_plot(P, BFData)
    % xw_rca_plot: display of xAM_imaging_RCA.m. For every mode (B-mode, xAM) three
    % orthogonal slices of the volume: depth against the first and the second
    % axis, and the plane at one depth. The sliders at the bottom of the figure
    % move the slices. Called by VSX as a process, and by xw_change_dr.

    if nargin == 0
        P = evalin('base', 'P');
        BFData = evalin('base', 'BFData');
    end
    UISTATES = evalin_if_exist('base', 'UISTATES', struct('dr_xam', 25, 'dr_bmode', 40));

    modes = fieldnames(BFData);
    modes(contains(modes, 'TimeTag')) = [];
    nmodes = numel(modes);
    names = {'x', 'y'}; % axis of the elements that transmit first, and second
    if P.first_orientation == 2, names = fliplr(names); end

    persistent f ax imgh sl modes_prev time_tag_array fps_tit
    if isempty(f) || ~isvalid(f) || ~isequal(modes_prev, modes)
        modes_prev = modes;
        time_tag_array = NaN(10, 1);
        time_tag_array(1) = BFData.TimeTag;
        [nz, ns, nf] = size(BFData.(modes{1}), [1 2 3]);

        f = figure(); clf;
        f.Position = [30 100 1350 800];
        f.UserData = struct('index', [round(nz / 2), round(ns / 2), round(nf / 2)]); % depth, second, first axis
        ax = gobjects(nmodes, 3);
        imgh = gobjects(nmodes, 3);
        z_mm = P.z_axis * 1e3; a_mm = P.axis_first * 1e3; b_mm = P.axis_second * 1e3;
        for k = 1:nmodes
            mode_str = strrep(modes{k}, 'PW', 'BMode');
            plane = {{a_mm, z_mm, [names{1} ' [mm]'], 'Depth [mm]', 'z-first'}, ...
                {b_mm, z_mm, [names{2} ' [mm]'], 'Depth [mm]', 'z-second'}, ...
                {a_mm, b_mm, [names{1} ' [mm]'], [names{2} ' [mm]'], 'first-second'}};
            for j = 1:3
                ax(k, j) = subplot(nmodes, 3, (k - 1) * 3 + j);
                imgh(k, j) = imagesc(plane{j}{1}, plane{j}{2}, zeros(numel(plane{j}{2}), numel(plane{j}{1})));
                xlabel(plane{j}{3}); ylabel(plane{j}{4});
                daspect([1 1 1]); colormap(ax(k, j), 'bone'); colorbar
                title(sprintf('%s, %s', strrep(mode_str, '_', ' '), plane{j}{5}))
            end
        end
        fps_tit = sgtitle(sprintf('Frame rate: %i fps', nan));

        % sliders: depth, second axis, first axis
        sl = gobjects(1, 3);
        lim = {[1 nz], [1 ns], [1 nf]};
        lab = {'Depth', [names{2} ' slice'], [names{1} ' slice']};
        for j = 1:3
            x0 = 0.1 + (j - 1) * 0.3;
            uicontrol(f, 'Style', 'text', 'Units', 'normalized', 'Position', [x0, 0.012, 0.08, 0.025], 'String', lab{j});
            sl(j) = uicontrol(f, 'Style', 'slider', 'Units', 'normalized', 'Position', [x0 + 0.08, 0.015, 0.17, 0.02], ...
                'Min', lim{j}(1), 'Max', lim{j}(2), 'Value', f.UserData.index(j), ...
                'SliderStep', [1, 10] / max(1, diff(lim{j})), 'Callback', @(src, ~) move_slice(src, j));
        end
    else
        if BFData.TimeTag ~= time_tag_array(end) % not a redraw of the same frame (sliders, dynamic range)
            time_tag_array = circshift(time_tag_array, -1);
            time_tag_array(end) = BFData.TimeTag;
            fps = 1 ./ mean(diff(time_tag_array), 'omitnan');
            fps_tit.String = sprintf('Frame rate: %.2f fps', fps);
        end
        XWSweep = evalin_if_exist('base', 'XWSweep', struct('active', false));
        if XWSweep.active
            p = XWSweep.steps(XWSweep.step, 1); vi = XWSweep.steps(XWSweep.step, 2);
            fps_tit.String = sprintf('%s  |  SWEEP pass %i/%i, %.2f V (%i/%i), %s', fps_tit.String, p, XWSweep.passes, ...
                XWSweep.hv_set(p, vi), vi, numel(XWSweep.voltages), XWSweep.phase);
        end
        XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
        if XWRecord.active
            fps_tit.String = sprintf('%s  |  REC %i/%i (%s)', fps_tit.String, ...
                XWRecord.frame_count, XWRecord.num_frames, XWRecord.mode);
        end
    end

    % log compress each volume relative to its maximum, show the slices
    idx = f.UserData.index;
    for k = 1:numel(modes)
        v = flogc(BFData.(modes{k})(:, :, :, 1));
        imgh(k, 1).CData = squeeze(v(:, idx(2), :));
        imgh(k, 2).CData = squeeze(v(:, :, idx(3)));
        imgh(k, 3).CData = squeeze(v(idx(1), :, :));
        DR = UISTATES.dr_bmode;
        if strcmp(modes{k}, 'xAM'), DR = UISTATES.dr_xam; end
        for j = 1:3, caxis(ax(k, j), [-DR 0]); end
    end
    f.UserData.last = BFData;

    function move_slice(src, j)
        f.UserData.index(j) = round(src.Value);
        xw_rca_plot(P, f.UserData.last)
    end
end
