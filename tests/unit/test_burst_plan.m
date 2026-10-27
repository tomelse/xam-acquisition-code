function tests = test_burst_plan
    tests = functiontests(localfunctions);
end

function test_default_burst(testCase)
    plan = xw_burst_plan(10, 46, 0);
    verifyEqual(testCase, plan.num_frames, 56);
    verifyEqual(testCase, plan.profile, [ones(1, 10), 2 * ones(1, 46)]);
    % set at the start of the burst, and before the first collapse frame
    verifyEqual(testCase, find(plan.switch_before), [1 11]);
    verifyEqual(testCase, plan.switch_before([1 11]), [1 2]);
end

function test_voltage_returns_after_collapse(testCase)
    plan = xw_burst_plan(2, 3, 2);
    verifyEqual(testCase, plan.profile, [1 1 2 2 2 1 1]);
    verifyEqual(testCase, plan.switch_before, [1 0 2 0 0 1 0]);
end

function test_start_at_burst_voltage(testCase)
    plan = xw_burst_plan(0, 2, 0);
    verifyEqual(testCase, plan.profile, [2 2]);
    verifyEqual(testCase, plan.switch_before, [2 0]);
end

function test_invalid_counts(testCase)
    verifyError(testCase, @() xw_burst_plan(-1, 3, 0), '');
    verifyError(testCase, @() xw_burst_plan(2, 0, 2), '');
    verifyError(testCase, @() xw_burst_plan(2.5, 3, 0), '');
end
