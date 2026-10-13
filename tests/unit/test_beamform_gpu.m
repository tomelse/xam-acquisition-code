function tests = test_beamform_gpu
    % Unit tests for the gpuArray beamformer xw_beamform_gpu: same results as
    % the reference xw_beamform_cpu. Skipped without a usable GPU.
    tests = functiontests(localfunctions);
end

function setupOnce(t)
    [ok, msg] = xw_beamform_gpu_available();
    t.assumeTrue(ok, msg);
    rng(4);
    Fs = 62.5e6; fd = 15.625e6; Nz = 80; nR = 7; nA = 2; nCh = 32; NzRF = 600;
    t.TestData.BFC = struct('decimSampleRate', Fs, 'demodFrequency', fd, 'Nz_RF', NzRF, 'NAngles', nA, 'NRays', nR);
    z = (0:Nz - 1)' * 4 / Fs;
    t.TestData.LUT_T = single(z / 2 + rand(1, nR, nA) * 1e-6);
    LUT_R = single(z / 2 + 1e-6 + rand(1, nR, nCh) * 2e-6);
    LUT_R(rand(size(LUT_R)) < 0.2) = 0; % some elements outside the aperture
    t.TestData.LUT_R = LUT_R;
    t.TestData.RF = int16(randi([-2000 2000], NzRF * nA * nR * 2, nCh)); % 2 frames
end

function test_matches_cpu_reference(t)
    d = t.TestData;
    g = xw_beamform_gpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    c = xw_beamform_cpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    verifyFalse(t, isa(g, 'gpuArray'), 'result should be returned on the CPU');
    verifyClass(t, g, 'single');
    verifySize(t, g, size(c));
    verifyLessThan(t, max(abs(g(:) - c(:))) / max(abs(c(:))), 1e-5);
end

function test_changed_lut_is_used(t)
    d = t.TestData;
    xw_beamform_gpu(d.BFC, d.RF, d.LUT_T, d.LUT_R);
    LT = d.LUT_T * 1.02; % LUTs are cached on the GPU: a change must be picked up
    g = xw_beamform_gpu(d.BFC, d.RF, LT, d.LUT_R);
    c = xw_beamform_cpu(d.BFC, d.RF, LT, d.LUT_R);
    verifyLessThan(t, max(abs(g(:) - c(:))) / max(abs(c(:))), 1e-5);
end
