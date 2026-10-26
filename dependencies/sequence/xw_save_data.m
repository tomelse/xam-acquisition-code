function xw_save_data()
    % Callback of the 'Save Data' button. Configures the save menu for the
    % current save mode (UISTATES.save_mode) and opens it. Saves a snapshot of
    % the frozen sequence; use 'Record' to save a series of frames.
    UISTATES = evalin('base', 'UISTATES');
    S = evalin('base', 'SaveDataMenuSettings');
    S.checkboxes.vsx_pars = true;
    S.checkboxes.iqdata = false;
    switch UISTATES.save_mode
        case 'images'
            S.checkboxes.rcvdata = false;
            S.checkboxes.figfig = true;
            S.checkboxes.figpng = true;
            S.custom_variables = {'UISTATES', 'BFData', 'BFData_raw'};
        case 'rf'
            S.checkboxes.rcvdata = true; % all frames in the RcvBuffer
            S.checkboxes.figfig = false;
            S.checkboxes.figpng = true;
            S.checkboxes.compression = false; % compression is ~20x slower for RF
            S.custom_variables = {'UISTATES', 'BFData', 'BFData_raw'}; % also the image on screen
    end
    assignin('base', 'SaveDataMenuSettings', S);
    [~] = saveDataMenu('apply_settings'); % overrides the menu's remembered state
    saveDataMenu();
end
