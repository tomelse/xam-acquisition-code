function xw_rca_burst_save_image()
    % External process at the end of a burst of the RCA, called for every frame in
    % turn: reconstructs the next captured frame (xw_rca_burst_capture) and keeps
    % the volume [depth, second axis, first axis] in XWBurst.images
    % [depth, second axis, first axis, frames]. xw_rca_burst_finish saves them.
    persistent Rb
    if ~evalin('base', 'exist(''XWBurst'', ''var'') && XWBurst.active')
        return
    end
    B = evalin('base', 'XWBurst');
    k = B.image_count + 1;
    if k > B.num_frames || k > xw_get(B, 'capture_count', 0)
        return % more frames than captured, e.g. an aborted burst
    end
    if isempty(Rb)
        Rb = xw_rca_burst_reconstruct_setup(evalin('base', 'P'), evalin('base', 'Receive'), ...
            evalin('base', 'Trans'), evalin('base', 'TW'));
    end
    V = xw_rca_burst_reconstruct_frame(Rb, xw_rca_burst_rf('get', k));
    if k == 1
        B.images = zeros([size(V), B.num_frames], 'single');
        B.z_axis_burst = Rb.z_axis * 1e3; B.axis_first = Rb.axis_first * 1e3; B.axis_second = Rb.axis_second * 1e3; % [mm]
    end
    B.images(:, :, :, k) = V;
    B.image_count = k;
    assignin('base', 'XWBurst', B);
end

function v = xw_get(s, name, default)
    v = default;
    if isfield(s, name) && ~isempty(s.(name)), v = s.(name); end
end
