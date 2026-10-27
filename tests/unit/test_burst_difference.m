function tests = test_burst_difference
    tests = functiontests(localfunctions);
end

function test_first_collapse_frame_minus_the_next_ones(testCase)
    images = repmat(reshape(1:56, 1, 1, 56), 2, 3); % frame k has the value k
    D = xw_burst_difference(images, 10, 46); % the default burst
    verifyEqual(testCase, D.frame, 11);
    verifyEqual(testCase, D.reference, 12:56);
    verifyEqual(testCase, D.difference, 11 - 34 * ones(2, 3)); % 11 - mean(12:56)
end

function test_frames_after_the_burst_voltage_are_not_used(testCase)
    images = repmat(reshape(1:9, 1, 1, 9), 2, 2);
    D = xw_burst_difference(images, 3, 4); % frames 1-3 pre, 4-7 at the burst voltage, 8-9 post
    verifyEqual(testCase, D.reference, 5:7);
end

function test_incomplete_burst(testCase)
    images = repmat(reshape(1:9, 1, 1, 9), 2, 2);
    D = xw_burst_difference(images(:, :, 1:5), 3, 4); % aborted after 5 frames
    verifyEqual(testCase, D.reference, 5);
    D = xw_burst_difference(images(:, :, 1:4), 3, 4);
    verifyEmpty(testCase, D.reference);
    verifyEmpty(testCase, D.difference);
end
