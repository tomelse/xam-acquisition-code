function v = xw_parse_voltages(str)
    % v = xw_parse_voltages(str)
    %   Parse a list of voltages: 'start:step:stop', 'start:stop' (1 V steps)
    %   or a list separated by commas or spaces ('2,3,5' or '2 3 5'). Returns
    %   [] for an empty string. Does not evaluate the string as MATLAB code.
    str = strtrim(char(str));
    if isempty(str)
        v = [];
        return
    end
    if contains(str, ':')
        parts = str2double(strsplit(str, ':'));
        if any(isnan(parts)) || ~ismember(numel(parts), [2 3])
            error('xw_sweep:parse', 'Could not read voltages "%s": use start:step:stop, e.g. 2:0.5:6', str);
        end
        if numel(parts) == 2
            parts = [parts(1), 1, parts(2)];
        end
        v = parts(1):parts(2):parts(3) + 1e-9; % include stop despite rounding
        v = round(v, 6);
    else
        v = str2double(strsplit(str, {',', ' '}, 'CollapseDelimiters', true));
        if any(isnan(v))
            error('xw_sweep:parse', 'Could not read voltages "%s": use a list like 2,3,5', str);
        end
    end
    if isempty(v)
        error('xw_sweep:parse', 'No voltages in "%s"', str);
    end
end
