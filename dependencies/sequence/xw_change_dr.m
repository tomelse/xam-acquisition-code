function xw_change_dr(src, value)
    UISTATES = evalin('base', 'UISTATES');
    % update UI State
    switch src
        case 'bmode'
            UISTATES.dr_bmode = value;
        case 'xam'
            UISTATES.dr_xam = value;
    end
    % make persistent
    assignin('base', 'UISTATES', UISTATES);
    P = evalin('base', 'P');
    if isfield(P, 'plot_function') % other display, e.g. xAM_imaging_RCA.m
        feval(P.plot_function);
    else
        xw_plot(); % update plot
    end
end
