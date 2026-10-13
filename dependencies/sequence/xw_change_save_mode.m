function xw_change_save_mode(UIState)
    % Callback of the 'Save mode' button group. The button order is
    % UISTATES.save_mode_order (the initial mode is listed first). Applies to
    % 'Save Data' and 'Record'; the voltage sweep uses P.sweep_save_mode.
    UISTATES = evalin('base', 'UISTATES');
    modes = {'images', 'rf'};
    if isfield(UISTATES, 'save_mode_order'); modes = UISTATES.save_mode_order; end
    UISTATES.save_mode = modes{UIState};
    assignin('base', 'UISTATES', UISTATES);
end
