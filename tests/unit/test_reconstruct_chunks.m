function tests = test_reconstruct_chunks
    % Unit tests for reconstructing a frame in groups of rays (chunks) and for
    % the receive buffer layouts: all give the same images as the whole frame.
    tests = functiontests(localfunctions);
end

function setup(t)
    rng(5);
    nR = 7; nA = 2; nCh = 12; Nz_RF = 128; Nz = 20;
    R.P = struct('num_rays', nR, 'num_angles', nA);
    R.BFC = struct('decimSampleRate', 62.5e6, 'demodFrequency', 15.625e6, 'Nz_RF', Nz_RF, ...
        'NAngles', nA, 'NRays', nR, 'Nz', Nz);
    R.modes = {'PW', 'xBmode', 'xAM'};
    R.LUT.TX = single(1e-6 * rand(Nz, nR, nA));
    R.LUT.RX = single(1e-6 * rand(Nz, nR, nCh) + 2e-6);
    R.beamform = @xw_beamform_cpu;
    R.beamformer = 'cpu';
    R.layout = 'ray-major';
    t.TestData.R = R;
    t.TestData.RF = int16(randi([-500 500], 3 * nR * nA * Nz_RF, nCh)); % ray-major frame
end

function test_chunks_make_the_same_image_as_the_frame(t)
    R = t.TestData.R; RF = t.TestData.RF;
    full = xw_reconstruct_frame(R, [int16(zeros(2, 12)); RF(3:end, :)]);
    for num_chunks = [1 3 7 20]
        Rc = xw_reconstruct_chunks(R, num_chunks);
        verifyEqual(t, numel(Rc.chunks), min(num_chunks, 7));
        for mode = R.modes
            img = complex(zeros(20, 7, 'single'));
            for k = 1:numel(Rc.chunks)
                IQ = xw_reconstruct_chunk(Rc, RF, k);
                img(:, Rc.chunks(k).rays) = IQ.(mode{1});
            end
            verifyEqual(t, img, full.(mode{1}), 'AbsTol', 1e-4 * max(abs(full.(mode{1})(:))));
        end
    end
end

function test_pulse_major_data_gives_the_same_image(t)
    R = t.TestData.R; RF = t.TestData.RF;
    nR = 7; nA = 2; Nz_RF = 128; nCh = 12;
    % ray-major [samples*angles, pulse, ray] -> pulse-major [samples*angles, ray, pulse]
    pm = reshape(permute(reshape(RF, nA * Nz_RF, 3, nR, nCh), [1 3 2 4]), [], nCh);
    Rp = R; Rp.layout = 'pulse-major';
    a = xw_reconstruct_frame(R, RF);
    b = xw_reconstruct_frame(Rp, pm);
    for mode = R.modes
        verifyEqual(t, a.(mode{1}), b.(mode{1}));
    end
end

function test_chunk_rays(t)
    verifyEqual(t, xw_chunk_rays(10, 3), {1:3, 4:7, 8:10});
    verifyEqual(t, xw_chunk_rays(5, 1), {1:5});
    verifyEqual(t, xw_chunk_rays(3, 8), {1, 2, 3});
end

function test_chunks_need_the_ray_major_layout(t)
    R = t.TestData.R; R.layout = 'pulse-major';
    R = xw_reconstruct_chunks(R, 4);
    verifyEmpty(t, R.chunks);
end
