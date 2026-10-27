function xw_set_start_event(event_num)
    % Restart the sequence at event event_num the next time VSX returns to MATLAB
    % (the Control command 'set&Run', as used for the start event in the
    % Verasonics example scripts).

    % VSX clears Control while it builds the GUI, so it may not exist yet.
    Control = evalin_if_exist('base', 'Control', struct('Command', [], 'Parameters', []));
    if isempty(Control(1).Command); nc = 1; else; nc = numel(Control) + 1; end
    Control(nc).Command = 'set&Run';
    Control(nc).Parameters = {'Parameters', 1, 'startEvent', event_num};
    assignin('base', 'Control', Control);
end
