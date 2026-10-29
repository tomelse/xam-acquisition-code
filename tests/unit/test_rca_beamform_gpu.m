function tests = test_rca_beamform_gpu
    % Unit tests for the gpuArray version of the RCA beamformer xw_rca_beamform_gpu: same
    % results as the reference xw_rca_beamform_cpu. Skipped without a usable GPU.
    tests = functiontests(localfunctions);
end

function setupOnce(t)
    [ok, msg] = xw_beamform_gpu_available();
    t.assumeTrue(ok, msg);
    rng(5);
    Fs = 62.5e6; fd = 15.625e6; Nz = 60; Nx = 9; nR = 5; nA = 2; nCh = 24; NzRF = 500;
    t.TestData.BFC = struct('decimSampleRate', Fs, 'demodFrequency', fd, 'Nz_RF', NzRF, 'NAngles', nA, 'NRays', nR);
    z = (0:Nz - 1)' * 4 / Fs;
    t.TestData.LUT_T = single(z / 2 + rand(1, nR, nA) * 1e-6); % [Nz, rays, angles]
    LUT_R = single(z / 2 + 1e-6 + rand(1, Nx, nCh) * 2e-6); % [Nz, Nx, channels]
    LUT_R(rand(size(LUT_R)) < 0.2) = 0; % some elements outside the f-number
    t.TestData.LUT_R = LUT_R;
    t.TestData.RF = int16(randi([-2000 2000], NzRF * nA * nR * 2, nCh)); % 2 frames
end

function test_matches_cpu_reference(t)
    d = t.TestData;
    g = xw_rca_beamform_gpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    c = xw_rca_beamform_cpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    verifyFalse(t, isa(g, 'gpuArray'), 'result should be returned on the CPU');
    verifyClass(t, g, 'single');
    verifySize(t, g, size(c));
    verifyLessThan(t, max(abs(g(:) - c(:))) / max(abs(c(:))), 1e-5);
end

function test_tables_on_the_gpu(t)
    % the tables can be kept on the GPU (xw_rca_reconstruct_setup does)
    d = t.TestData;
    g = xw_rca_beamform_gpu(d.BFC, d.RF, gpuArray(d.LUT_T), gpuArray(d.LUT_R));
    c = xw_rca_beamform_cpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    verifyLessThan(t, max(abs(g(:) - c(:))) / max(abs(c(:))), 1e-5);
end

function test_reconstruct_setup_with_the_gpu(t)
    % xw_rca_reconstruct_setup with the GPU gives the same volume as with the CPU
    nh = 16; pitch = 0.2; f0 = 6; c = 1540;
    Trans.type = 4; Trans.numelements = 2 * nh; Trans.spacingMm = pitch; Trans.frequency = f0;
    Trans.lensCorrection = 0; Trans.units = 'mm';
    pos = pitch * ((-(nh - 1) / 2):((nh - 1) / 2))';
    Trans.ElementPos = zeros(2 * nh, 5); Trans.ElementPos(1:nh, 1) = pos; Trans.ElementPos(nh + 1:end, 2) = pos;
    Trans.Connector = flipud((1:2 * nh)'); TW(1).peak = 0;
    Receive(1).decimSampleRate = 25; Receive(1).demodFrequency = 6.25; Receive(1).endSample = 512; Receive(1).datatype = 'int16';
    P.first_orientation = 1; P.speed_of_sound = c; P.scale_wvl2mm = c / f0 * 1e-3;
    P.image_start_depth_mm = 0; P.image_end_depth_mm = 8;
    P.ray_positions = 5:12; P.num_rays = numel(P.ray_positions); P.num_angles = 1; P.num_chunks = 4;
    P.ray_half_aperture = 4 * ones(1, P.num_rays); P.ray_angle = 17 * ones(1, P.num_rays);
    P.beamform_image_modes = {'PW', 'xAM'};
    rng(6);
    RF = int16(randi([-500 500], 3 * 2 * P.num_rays * 512, 2 * nh));
    Rc = xw_rca_reconstruct_setup(P, Receive, Trans, TW, 'cpu');
    Rg = xw_rca_reconstruct_setup(P, Receive, Trans, TW, 'gpu');
    Bc = xw_rca_reconstruct_frame(Rc, RF);
    Bg = xw_rca_reconstruct_frame(Rg, RF);
    for mode = {'PW', 'xAM'}
        verifyLessThan(t, max(abs(Bg.(mode{1})(:) - Bc.(mode{1})(:))) / max(abs(Bc.(mode{1})(:))), 1e-4);
    end
end
