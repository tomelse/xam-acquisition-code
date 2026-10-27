function xw_burst_preview(imData)
    % External process during a burst: shows the latest reconstructed frame in the
    % 'Burst preview' window. It is not saved; the burst is reconstructed again at the end.
    persistent f ax imgh
    B = evalin_if_exist('base', 'XWBurst', struct('active', false));
    if ~B.active, return, end
    UISTATES = evalin_if_exist('base', 'UISTATES', struct('dr_bmode', 40));
    img = flogc(double(imData(:, :, 1))); % [dB], compressed
    if isempty(f) || ~isvalid(f) || ~isvalid(ax)
        f = figure('Name', 'Burst preview', 'NumberTitle', 'off');
        ax = axes(f);
        imgh = imagesc(ax, B.x_axis, B.z_axis, img);
        xlabel(ax, 'Lateral position [mm]'); ylabel(ax, 'Depth [mm]');
        daspect(ax, [1 1 1]); colormap(ax, 'hot'); colorbar(ax);
    else
        imgh.CData = img;
    end
    caxis(ax, [-UISTATES.dr_bmode 0]);
    title(ax, 'Burst preview (latest frame)');
    drawnow limitrate
end
