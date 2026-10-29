function tests = test_rca_burst
    % Unit tests for the burst of the row-column array (RCA): the sequence structures of
    % xw_rca_setup_burst, and the reconstruction of a frame (xw_rca_burst_reconstruct_*)
    % on synthetic data: a scatterer must appear at its position in the volume.
    tests = functiontests(localfunctions);
end

function setup(t)
    nh = 16; pitch = 0.2; f0 = 6; c = 1540;
    Trans.type = 4; Trans.numelements = 2 * nh; Trans.spacingMm = pitch; Trans.frequency = f0;
    Trans.lensCorrection = 0; Trans.units = 'mm';
    pos = pitch * ((-(nh - 1) / 2):((nh - 1) / 2))';
    Trans.ElementPos = zeros(2 * nh, 5);
    Trans.ElementPos(1:nh, 1) = pos;
    Trans.ElementPos(nh + 1:end, 2) = pos;
    Trans.Connector = flipud((1:2 * nh)');

    P.first_orientation = 1; P.speed_of_sound = c;
    P.scale_wvl2mm = c / f0 * 1e-3; P.scale_mm2wvl = f0 / (c * 1e-3);
    P.burst_start_depth_mm = 1; P.burst_end_depth_mm = 8; P.burst_num_tx = 8; P.burst_focus_mm = 4;
    P.burst_tw_half_cycles = 7; P.transmit_frequency = f0; P.demod_ratio = 1; P.use_cpu_beamformer = true;

    G = xw_rca_geometry(Trans, 1);
    stub = @(tx) 5 * (1 - ((1:numel(tx.Apod)) - mean(find(tx.Apod))) .^ 2 / 100) .* (tx.Apod > 0); % a delay profile, largest in the centre
    S = xw_rca_setup_burst(P, Trans, G, 2, 100, 40, stub);
    P.burst_ray_centers = S.ray_centers; P.burst_delay_centre = S.delay_centre; P.burst_first_receive = 1;
    Receive(1).decimSampleRate = 25; Receive(1).demodFrequency = 6.25; Receive(1).endSample = 512;
    TW(2).peak = 0;
    t.TestData = struct('P', P, 'Trans', Trans, 'G', G, 'S', S, 'Receive', Receive, 'TW', TW, 'nh', nh);
end

function test_transmit_structures(t)
    d = t.TestData; S = d.S; nr = S.num_rays;
    verifyEqual(t, nr, d.nh - 8 + 1);
    verifyEqual(t, numel(S.TX), 2 * 3 * nr);
    for o = 1:2
        tx_el = d.G.tx_elements{o}; rx_el = d.G.rx_elements{o};
        for n = [1 nr]
            a1 = S.TX(S.tx_index(o, 1, n) - 100).Apod; a2 = S.TX(S.tx_index(o, 2, n) - 100).Apod; a3 = S.TX(S.tx_index(o, 3, n) - 100).Apod;
            ap = tx_el(n:n + 7);
            verifyEqual(t, find(a1), ap, 'full aperture of the half of the transmit orientation');
            verifyEqual(t, find(a2), ap(2:2:end), 'odd elements off');
            verifyEqual(t, find(a3), ap(1:2:end), 'even elements off');
            verifyEmpty(t, intersect(find(a1), rx_el));
        end
    end
    verifyEqual(t, S.TX(1).Origin(2:3), [0 0], 'x half: the focal point is given by x');
    verifyEqual(t, S.TX(S.tx_index(2, 1, 1) - 100).Origin([1 3]), [0 0], 'y half: the focal point is given by y');
    verifyEqual(t, S.ray_centers{1}, S.ray_centers{2}, 'AbsTol', 1e-12);
    verifyGreaterThan(t, min(S.delay_centre(:)), 0);
end

function test_receive_structures(t)
    d = t.TestData; S = d.S; nr = S.num_rays;
    verifyEqual(t, numel(S.Receive), 2 * 3 * nr * 2);
    for o = 1:2
        rx = d.G.rx_elements{o};
        for pulse = 1:3
            r = S.Receive(S.rcv_index(o, pulse, 3, 2) - 40);
            verifyEqual(t, r.bufnum, 2); verifyEqual(t, r.framenum, 2); verifyEqual(t, r.acqNum, (o - 1) * nr + 3);
            verifyEqual(t, r.mode, double(pulse > 1));
            verifyEqual(t, r.Apod(rx), (1 - 2 * (pulse > 1)) * ones(1, d.nh), 'receive with the other half, inverted for pulse 2 and 3');
            verifyEqual(t, nnz(r.Apod), d.nh);
        end
    end
    verifyEqual(t, S.rcv_index(1, 1, 1, 1), 41);
    min_rows = 2 * nr * ceil(ceil(sqrt((8 * 3.896) ^ 2 + (15 * 0.2 * 3.896) ^ 2)) * 8 / 128) * 128;
    verifyGreaterThanOrEqual(t, S.rows_per_frame, min_rows, 'room for the acquisitions with a margin');
    verifyEqual(t, mod(S.rows_per_frame, 2 * nr * 128), 0, 'a multiple of 128 samples per acquisition');
end

function test_scatterer_is_at_its_position(t)
    d = t.TestData; nr = d.S.num_rays;
    Rb = xw_rca_burst_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    ia = 3; ib = 6; iz = 30; Fs = Rb.BFC.decimSampleRate; fd = Rb.BFC.demodFrequency; Nz_RF = Rb.BFC.Nz_RF;
    RF = zeros(2 * nr * Nz_RF, d.nh);
    n = (0:Nz_RF - 1)' / Fs;
    for o = 1:2
        if o == 1, ray = ia; out = ib; else, ray = ib; out = ia; end
        rows = (o - 1) * nr * Nz_RF + (ray - 1) * Nz_RF + (1:Nz_RF);
        for e = 1:d.nh
            t_echo = double(Rb.LUT_T{o}(iz, ray) + Rb.LUT_R{o}(iz, out, e));
            if t_echo == 0, continue, end
            RF(rows, e) = 3000 * cos(2 * pi * fd * (n - t_echo)) .* exp(-((n - t_echo) * fd / 1.5) .^ 2);
        end
    end
    V = xw_rca_burst_reconstruct_frame(Rb, int16(RF));
    verifySize(t, V, [numel(Rb.z_axis), nr, nr]);
    [~, i] = max(V(:));
    [zi, bi, ai] = ind2sub(size(V), i);
    verifyLessThanOrEqual(t, abs(zi - iz), 1);
    verifyEqual(t, [bi, ai], [ib, ia]);
end

function test_frame_size_is_checked(t)
    d = t.TestData;
    Rb = xw_rca_burst_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    verifyError(t, @() xw_rca_burst_reconstruct_frame(Rb, zeros(10, d.nh, 'int16')), 'xw_rca:burstrows');
    % rows after the last acquisition are ignored
    verifyWarningFree(t, @() xw_rca_burst_reconstruct_frame(Rb, zeros(2 * d.S.num_rays * Rb.BFC.Nz_RF + 300, d.nh, 'int16')));
end

function test_rf_store(t) %#ok<INUSD>
    xw_rca_burst_rf('reset', 4, 2, 3);
    xw_rca_burst_rf('set', 2, int16([1 2; 3 4; 5 6; 7 8]));
    verifyEqual(t, xw_rca_burst_rf('get', 2), int16([1 2; 3 4; 5 6; 7 8]));
    verifyEqual(t, xw_rca_burst_rf('get', 1), zeros(4, 2, 'int16'));
    xw_rca_burst_rf('clear');
end
