function xw_change_save_mode(UIState)
    % Callback of the 'Save mode' button group: 1 = xAM images, 2 = raw RF.
    % Applies to both 'Save Data' and 'Record'.
    UISTATES = evalin('base', 'UISTATES');
    modes = {'images', 'rf'};
    UISTATES.save_mode = modes{UIState};
    assignin('base', 'UISTATES', UISTATES);
end
