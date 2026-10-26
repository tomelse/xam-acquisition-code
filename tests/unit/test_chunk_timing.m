function tests = test_chunk_timing
    % xw_chunk_timing (used by the hardware test) on synthetic time tags.
    tests = functiontests(localfunctions);
end

function test_timing_from_time_tags(t)
    P = struct('num_rays', 6, 'num_angles', 1, 'num_chunks', 3, 'Nz_RF', 16, 'ttna', 200);
    n_acq = 3 * 6; per_chunk = 3 * 2;
    % acquisition times: ttna apart, 1 ms extra pause before the 2nd chunk, 0.5 ms before the 3rd
    pauses = zeros(1, n_acq); pauses(per_chunk + 1) = 1e-3; pauses(2 * per_chunk + 1) = 0.5e-3;
    tags_s = 100 + (0:n_acq - 1) * 200e-6 + cumsum(pauses);
    ticks = round(tags_s * 4e4);
    RF = zeros(n_acq * 16, 4, 'int16');
    for a = 1:n_acq
        lo = mod(ticks(a), 65536); hi = floor(ticks(a) / 65536);
        RF((a - 1) * 16 + (1:2), 1) = typecast(uint16([lo hi]), 'int16'); % two int16 samples: low word, high word
    end
    C = xw_chunk_timing(P, RF);
    verifyTrue(t, C.increasing);
    verifyEqual(t, C.within_chunk, 200e-6, 'AbsTol', 25e-6);
    verifyEqual(t, C.pause(:, 1)', [1e-3 0.5e-3], 'AbsTol', 25e-6);
    verifyEqual(t, C.num_chunks, 3);
end
