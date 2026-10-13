function S = xw_sweep_next_step(S)
    % Set the voltage for sweep step S.step and wait for it to settle. A
    % voltage change reaches the hardware only when VSX next returns to
    % MATLAB, and frames already in flight use the old voltage, so the first
    % S.settle_frames frames and S.settle_s seconds are discarded (longer when
    % the voltage goes down, which takes the supply longer).
    p = S.steps(S.step, 1);
    vi = S.steps(S.step, 2);
    TPC = evalin('base', 'TPC');
    hv_previous = TPC(1).hv;

    S.hv_set(p, vi) = xw_sweep_set_voltage(S.voltages(vi));
    if abs(S.hv_set(p, vi) - S.voltages(vi)) > 0.05
        fprintf(2, 'Sweep: requested %.2f V, but %.2f V was set (TPC limit)\n', S.voltages(vi), S.hv_set(p, vi));
    end

    S.settle_needed_s = S.settle_s;
    if S.hv_set(p, vi) < hv_previous - 0.05
        S.settle_needed_s = S.settle_s_down;
    end
    S.phase = 'settle';
    S.phase_frames = 0;
    S.t_set = tic;
    fprintf('Sweep pass %i/%i: %.2f V (%i/%i)\n', p, S.passes, S.hv_set(p, vi), vi, numel(S.voltages));
end
