function xw_sequence_start(hObject)
    EN = evalin('base', 'EN');
    fprintf('Starting acquisition\n')

    % restarting during a burst abandons it (xw_burst_finish saves the frames so far)
    if evalin_if_exist('base', 'XWBurst', struct('active', false)).active
        fprintf('Burst aborted by restarting the sequence\n')
        xw_burst_finish('aborted', false);
    end

    xw_set_start_event(EN.StartEvent); % Event number that corresponds to start sequence

    % reset StatusDisplay
    %StatusDisplay(true);

    % unfreeze. Vantage has a 'Freeze' button, Vantage NXT may tag it 'toggleFreeze'
    gui = ancestor(hObject, 'figure'); % handle to gui
    freezeBut = [findobj(gui, 'String', 'Freeze'); findobj(gui, 'Tag', 'toggleFreeze')];
    set(freezeBut, 'Value', 0);
    assignin('base', 'freeze', 0);
    xw_burst_update_button();
end
