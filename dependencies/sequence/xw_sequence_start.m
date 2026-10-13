function xw_sequence_start(hObject)
    EN = evalin('base', 'EN');
    fprintf('Starting acquisition\n')
    eventNum = EN.StartEvent;

    % create control struct. VSX clears Control while it builds the GUI, so it
    % may not exist yet.
    Control = evalin_if_exist('base', 'Control', struct('Command', [], 'Parameters', []));
    if isempty(Control(1).Command); nc = 1; else; nc = numel(Control) + 1; end
    Control(nc).Command = 'set&Run';
    Control(nc).Parameters = {'Parameters', 1, 'startEvent', eventNum}; % Event number that corresponds to start sequence
    assignin('base', 'Control', Control);

    % reset StatusDisplay
    %StatusDisplay(true);

    % unfreeze. Vantage has a 'Freeze' button, Vantage NXT may tag it 'toggleFreeze'
    gui = ancestor(hObject, 'figure'); % handle to gui
    freezeBut = [findobj(gui, 'String', 'Freeze'); findobj(gui, 'Tag', 'toggleFreeze')];
    set(freezeBut, 'Value', 0);
    assignin('base', 'freeze', 0);
end
