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

function test_half_data_gives_the_same_image_as_int16(t)
    % half data is the 22 bit value / 256; integers / 256 are exact in half, so the
    % same images are expected (the first two samples of every acquisition,
    % holding the time tag, are not used)
    R = t.TestData.R; RF = t.TestData.RF;
    Rh = R; Rh.rf_datatype = 'half';
    Rh = xw_reconstruct_chunks(Rh, 3);
    a = xw_reconstruct_frame(R, RF);
    b = xw_reconstruct_frame(Rh, half_bits(RF, -8));
    c = xw_reconstruct_chunk(Rh, half_bits(RF, -8), 2);
    for mode = R.modes
        verifyEqual(t, b.(mode{1}), a.(mode{1}), 'AbsTol', 1e-4 * max(abs(a.(mode{1})(:))));
        verifyEqual(t, c.(mode{1}), a.(mode{1})(:, Rh.chunks(2).rays), 'AbsTol', 1e-4 * max(abs(a.(mode{1})(:))));
    end
end

function test_time_tag_samples_of_half_data_are_ignored(t)
    R = t.TestData.R; RF = t.TestData.RF;
    Rh = R; Rh.rf_datatype = 'half';
    H = half_bits(RF, -8);
    H(1:2, 1) = int16([-1; 32767]); % bit patterns that would be NaN as half data
    b = xw_reconstruct_frame(Rh, H);
    verifyTrue(t, all(isfinite(b.xAM(:))));
end

function test_half2single(t)
    H = half_bits(int16([0 1 -1 2 -2 100 -500 2047]'), 0);
    verifyEqual(t, xw_half2single(H, 'matlab'), single([0 1 -1 2 -2 100 -500 2047]'));
    % special values: 65504 (largest), 2^-14 (smallest normal), 2^-24 (smallest subnormal), +-Inf, NaN
    S = xw_half2single(typecast(uint16([hex2dec('7BFF') hex2dec('0400') hex2dec('0001') hex2dec('7C00') hex2dec('FC00') hex2dec('7E00')]), 'int16'), 'matlab');
    verifyEqual(t, S(1:5), single([65504 2^-14 2^-24 Inf -Inf]));
    verifyTrue(t, isnan(S(6)));
    if exist('convertHalfRcvData', 'file') == 3 % Vantage software on the path
        X = int16(randi([-32768 32767], 50, 4));
        X(isnan(xw_half2single(X, 'matlab'))) = 0;
        verifyEqual(t, convertHalfRcvData(X, 'single'), xw_half2single(X, 'matlab'));
    end
end

function H = half_bits(I, shift)
    % bit patterns of the integers * 2^shift (|I| < 2048, exact in half) as half data in int16
    if nargin < 2, shift = 0; end
    a = double(abs(I)); e = floor(log2(max(a, 1)));
    bits = (e + shift + 15) * 1024 + round((a ./ 2 .^ e - 1) * 1024);
    bits(a == 0) = 0;
    H = typecast(uint16(bits(:) + 32768 * (I(:) < 0)), 'int16');
    H = reshape(H, size(I));
end
