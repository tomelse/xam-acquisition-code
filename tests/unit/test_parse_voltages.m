function tests = test_parse_voltages
    % Unit tests for xw_parse_voltages (the run_xam.sh --sweep argument).
    tests = functiontests(localfunctions);
end

function test_range(t)
    verifyEqual(t, xw_parse_voltages('1.6:0.4:3.2'), [1.6 2.0 2.4 2.8 3.2], 'AbsTol', 1e-9);
end

function test_range_without_step(t)
    verifyEqual(t, xw_parse_voltages('2:5'), [2 3 4 5]);
end

function test_lists(t)
    verifyEqual(t, xw_parse_voltages('2,3,5'), [2 3 5]);
    verifyEqual(t, xw_parse_voltages('2 3  5'), [2 3 5]);
    verifyEqual(t, xw_parse_voltages(' 2.5 '), 2.5);
end

function test_empty_means_no_sweep(t)
    verifyEmpty(t, xw_parse_voltages(''));
end

function test_rejects_bad_input(t)
    verifyError(t, @() xw_parse_voltages('2:x:5'), 'xw_sweep:parse');
    verifyError(t, @() xw_parse_voltages('1:2:3:4'), 'xw_sweep:parse');
    verifyError(t, @() xw_parse_voltages('two'), 'xw_sweep:parse');
    verifyError(t, @() xw_parse_voltages('system(''ls'')'), 'xw_sweep:parse'); % never evaluated
end
