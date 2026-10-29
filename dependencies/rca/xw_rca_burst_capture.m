function xw_rca_burst_capture(RData)
    % External process during a burst of the RCA, after every frame of the burst
    % receive buffer: keeps the RF of the receive elements of that frame in host
    % memory (xw_rca_burst_rf). The frames are reconstructed after the burst, so
    % the acquisition does not wait for a reconstruction (the copy takes some
    % time: the host time of each frame is saved in burst.mat).
    persistent G
    B = evalin_if_exist('base', 'XWBurst', struct('active', false));
    if ~B.active, return, end
    if isempty(G)
        G = xw_rca_geometry(evalin('base', 'Trans'), evalin('base', 'P.first_orientation'));
    end
    P = evalin('base', 'P');
    nr = P.burst_num_rays_o; % rays per orientation
    Nz_RF = evalin('base', sprintf('Receive(%d).endSample', P.burst_first_receive)); % samples per acquisition, as given by VSX
    rows_o = nr * Nz_RF; % rows of one orientation; the rows after the last acquisition are not kept
    assert(size(RData, 1) >= 2 * rows_o, 'xw_rca_burst_capture: a frame has %i rows, expected at least %i', size(RData, 1), 2 * rows_o);

    k = xw_get(B, 'capture_count', 0) + 1;
    if k > B.num_frames, return, end
    if k == 1
        xw_rca_burst_rf('reset', 2 * rows_o, G.num_half, B.num_frames);
        B.capture_host_time = NaN(1, B.num_frames);
    end
    frame = zeros(2 * rows_o, G.num_half, 'int16');
    for o = 1:2
        rows = (o - 1) * rows_o + (1:rows_o);
        frame(rows, :) = RData(rows, G.rcv_cols{o});
    end
    xw_rca_burst_rf('set', k, frame);
    B.capture_count = k;
    B.capture_host_time(k) = posixtime(datetime('now'));
    assignin('base', 'XWBurst', B);
end

function v = xw_get(s, name, default)
    v = default;
    if isfield(s, name) && ~isempty(s.(name)), v = s.(name); end
end
