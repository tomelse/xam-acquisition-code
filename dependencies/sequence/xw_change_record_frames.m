function xw_change_record_frames(UIValue)
    % Callback of the 'Rec. frames' slider: number of frames saved per recording.
    UISTATES = evalin('base', 'UISTATES');
    UISTATES.record_num_frames = max(1, round(UIValue));
    assignin('base', 'UISTATES', UISTATES);
end
