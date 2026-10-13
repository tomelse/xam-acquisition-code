function hv_set = xw_sweep_set_voltage(hv)
    % hv_set = xw_sweep_set_voltage(hv)
    %   Set the transmit voltage of TPC profile 1 to hv [V] while running,
    %   using the same Verasonics function as the 'High Voltage P1' slider, and
    %   keep the slider in sync. The voltage is clamped to the TPC limits;
    %   hv_set is the value actually set. The change is sent to the hardware
    %   the next time VSX returns to MATLAB, so the frame already being
    %   acquired may still use the old voltage.
    %
    %   This changes the voltage of one profile at runtime instead of switching
    %   between fixed TPC profiles with 'setTPCProfile' (as in the BURST
    %   scripts): there are only 4 profiles, and a sweep needs more voltages.
    [result, hv_set] = setTpcProfileHighVoltage(hv, 1);
    if ~strcmpi(result, 'Success')
        error('xw_sweep:voltage', 'Could not set the transmit voltage to %.2f V: %s', hv, result);
    end

    % keep the VSX slider in sync (as the slider callback does)
    set(findobj('Tag', 'hv1Sldr'), 'Value', hv_set);
    set(findobj('Tag', 'hv1Value'), 'String', num2str(hv_set, '%.1f'));
    assignin('base', 'tStartHvSldr', tic); % VSX uses this to suppress errors right after a voltage change
end
