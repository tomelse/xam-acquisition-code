function tests = test_rca_reconstruct
    % Unit tests for the RCA reconstruction (xw_rca_reconstruct_setup /
    % xw_rca_reconstruct_frame) on synthetic data: a point scatterer must appear
    % at its position in the volume, for both orientations, with the hardware
    % channels in a different order than the elements.
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
    Trans.Connector = flipud((1:2 * nh)'); % hardware channel of every element
    TW(1).peak = 0;

    Receive(1).decimSampleRate = 25; Receive(1).demodFrequency = 6.25; Receive(1).endSample = 512;
    Receive(1).datatype = 'int16';

    P.first_orientation = 1; P.speed_of_sound = c; P.scale_wvl2mm = c / f0 * 1e-3;
    P.image_start_depth_mm = 0; P.image_end_depth_mm = 8;
    P.ray_positions = 5:12; P.num_rays = numel(P.ray_positions); P.num_angles = 1; P.num_chunks = 4;
    P.ray_half_aperture = 4 * ones(1, P.num_rays); P.ray_angle = 17 * ones(1, P.num_rays);
    P.use_cpu_beamformer = true; P.beamform_image_modes = {'PW', 'xAM'};

    t.TestData = struct('P', P, 'Trans', Trans, 'TW', TW, 'Receive', Receive, 'nh', nh);
end

function RF = synthetic_rf(R, ia, ib, iz)
    % echo of a scatterer at first-axis ray ia, second-axis ray ib, depth index iz, in the X pulse
    G = R.G; Fs = R.BFC.decimSampleRate; Nz_RF = R.BFC.Nz_RF; fd = R.BFC.demodFrequency;
    nR = R.P.num_rays;
    RF = zeros(3 * 2 * nR * Nz_RF, 2 * G.num_half);
    n = (0:Nz_RF - 1)' / Fs;
    for o = 1:2
        if o == 1, ray = ia; out = ib; else, ray = ib; out = ia; end
        global_ray = ray + (o - 1) * nR;
        rows = (global_ray - 1) * 3 * Nz_RF + (1:Nz_RF); % X pulse
        for e = 1:G.num_half
            t_echo = double(R.LUT.TX(iz, ray, 1) + R.LUT.RX{o}(iz, out, e));
            if t_echo == 0, continue, end % outside the f-number
            RF(rows, G.rcv_cols{o}(e)) = 3000 * cos(2 * pi * fd * (n - t_echo)) .* exp(-((n - t_echo) * fd / 1.5) .^ 2);
        end
    end
    RF = int16(RF);
end

function test_point_scatterer_is_at_its_position(t)
    d = t.TestData;
    R = xw_rca_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    ia = 3; ib = 6; iz = 40;
    BF = xw_rca_reconstruct_frame(R, synthetic_rf(R, ia, ib, iz));
    verifySize(t, BF.xAM, [numel(R.P.z_axis), d.P.num_rays, d.P.num_rays]); % [depth, second, first]
    [~, i] = max(BF.xAM(:));
    [zi, bi, ai] = ind2sub(size(BF.xAM), i);
    verifyLessThanOrEqual(t, abs(zi - iz), 1);
    verifyEqual(t, [bi, ai], [ib, ia]);
    verifyLessThan(t, max(BF.PW(:)), 1e-3 * max(BF.xAM(:)), 'the L and R pulses are empty');
end

function test_orientation_order(t)
    % transmitting with the other half first swaps the two lateral axes of the volume
    d = t.TestData;
    d.P.first_orientation = 2;
    R = xw_rca_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    verifyEqual(t, R.G.tx_elements{1}, d.nh + 1:2 * d.nh);
    verifyEqual(t, R.G.rx_elements{1}, 1:d.nh);
    ia = 2; ib = 7; iz = 30;
    BF = xw_rca_reconstruct_frame(R, synthetic_rf(R, ia, ib, iz));
    [~, i] = max(BF.xAM(:));
    [~, bi, ai] = ind2sub(size(BF.xAM), i);
    verifyEqual(t, [bi, ai], [ib, ia]);
end

function test_chunks_cover_all_rays(t)
    for num_chunks = [1 2 3 4 7 20]
        plan = xw_rca_chunk_plan(8, num_chunks);
        verifyEqual(t, sort([plan([plan.orientation] == 1).rays]), 1:8);
        verifyEqual(t, sort([plan([plan.orientation] == 2).rays]), 1:8);
        verifyEqual(t, sort([plan.global_rays]), 1:16);
        verifyTrue(t, all(arrayfun(@(c) all(diff(c.global_rays) == 1), plan)), 'rays of a chunk are consecutive');
    end
end

function test_chunked_equals_whole_frame(t)
    % the same volume for any number of chunks
    d = t.TestData;
    R4 = xw_rca_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    d.P.num_chunks = 2;
    R2 = xw_rca_reconstruct_setup(d.P, d.Receive, d.Trans, d.TW, 'cpu');
    RF = synthetic_rf(R4, 4, 5, 25);
    verifyEqual(t, xw_rca_reconstruct_frame(R4, RF).xAM, xw_rca_reconstruct_frame(R2, RF).xAM, 'AbsTol', 1e-2);
end
