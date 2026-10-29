function tests = test_rca_beamform
    % Unit tests for the row-column array (RCA) beamformer xw_rca_beamform_cpu and
    % its delay tables: a synthetic echo must be focused at the depth, receive
    % position and ray its delays belong to.
    tests = functiontests(localfunctions);
end

function setup(t)
    Fs = 62.5e6; fd = 15.625e6;
    t.TestData.BFC = struct('decimSampleRate', Fs, 'demodFrequency', fd, 'Nz_RF', 400, 'NAngles', 1, 'NRays', 3);
    Nz = 60; Nx = 5; nCh = 8;
    z_delay = (0:Nz - 1)' * 4 / Fs; % one depth pixel = 4 samples of two-way time
    t.TestData.LUT_T = single(repmat(z_delay / 2, 1, 3)); % [Nz, rays, angles]
    % receive delay depends on the output position, so that the focus is at the position that matches
    shift = reshape((0:Nx - 1) * 3 / Fs, 1, Nx); % 3 samples per output position
    t.TestData.LUT_R = single(repmat(z_delay / 2 + 1e-6 + shift, 1, 1, nCh)); % [Nz, Nx, channels], all elements active
    t.TestData.Fs = Fs; t.TestData.fd = fd; t.TestData.nCh = nCh; t.TestData.Nx = Nx;
end

function test_point_echo_is_focused(t)
    d = t.TestData;
    z_target = 37; x_target = 4; ray_target = 2;
    t_echo = double(d.LUT_T(z_target, ray_target) + d.LUT_R(z_target, x_target, 1));
    RF = zeros(d.BFC.Nz_RF, 3, d.nCh); % [samples, rays, channels]
    n = (0:d.BFC.Nz_RF - 1)' / d.Fs;
    burst = cos(2 * pi * d.fd * (n - t_echo)) .* exp(-((n - t_echo) * d.fd / 1.5) .^ 2);
    RF(:, ray_target, :) = repmat(3000 * burst, 1, 1, d.nCh);
    RF = int16(reshape(RF, [], d.nCh)); % ray-major like the receive buffer
    BF = xw_rca_beamform_cpu(d.BFC, RF, d.LUT_T, d.LUT_R);
    verifySize(t, BF, [size(d.LUT_T, 1), d.Nx, 3]);
    [~, i] = max(abs(BF(:)));
    [zi, xi, ri] = ind2sub(size(BF), i);
    verifyEqual(t, ri, ray_target);
    verifyLessThanOrEqual(t, abs(zi - z_target), 1);
    verifyEqual(t, xi, x_target);
    verifyLessThan(t, max(abs(BF(:, :, [1 3])), [], 'all'), 1e-3 * max(abs(BF(:))), 'other rays should be empty');
end

function test_frames_are_stacked(t)
    d = t.TestData;
    rng(2);
    RF1 = int16(randi([-100 100], d.BFC.Nz_RF * 3, d.nCh));
    RF2 = int16(randi([-100 100], d.BFC.Nz_RF * 3, d.nCh));
    BF = xw_rca_beamform_cpu(d.BFC, [RF1; RF2], d.LUT_T, d.LUT_R);
    verifySize(t, BF, [size(d.LUT_T, 1), d.Nx, 3, 2]);
    verifyEqual(t, BF(:, :, :, 2), xw_rca_beamform_cpu(d.BFC, RF2, d.LUT_T, d.LUT_R), 'AbsTol', 1e-3);
end
