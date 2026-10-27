function xw_burst_update_button()
    % Enable the 'Burst' button only when a burst can be started: the sequence
    % is running (not frozen) and nothing else is saving or changing the
    % voltage: no recording (including RF files still being written), no
    % voltage sweep and no burst. Called whenever one of these changes, and
    % for every frame by xw_beamform_run. VSX does not tell when Freeze is
    % pressed, so xw_burst_start checks that too.
    persistent h
    if isempty(h) || ~all(isgraphics(h))
        h = findall(groot, 'Tag', 'UserC4PushButton');
    end
    if isempty(h), return; end

    XWRecord = evalin_if_exist('base', 'XWRecord', struct('active', false));
    XWSweep = evalin_if_exist('base', 'XWSweep', struct('active', false));
    XWBurst = evalin_if_exist('base', 'XWBurst', struct('active', false));
    saving = XWRecord.active;
    if isfield(XWRecord, 'pending') && ~isempty(XWRecord.pending)
        saving = saving || any(arrayfun(@(f) ~strcmp(f.State, 'finished'), XWRecord.pending));
    end
    frozen = evalin_if_exist('base', 'freeze', 1);

    enable = ~(saving || XWSweep.active || XWBurst.active || frozen);
    set(h, 'Enable', ternary(enable, 'on', 'off'));
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
