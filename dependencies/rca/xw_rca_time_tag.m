function tt = xw_rca_time_tag(R, RFData)
    % tt = xw_rca_time_tag(R, RFData)
    %   Hardware time tag [s] of the first acquisition of a frame, read in the
    %   first receive channel of the first orientation (the first two samples
    %   of an acquisition hold the time tag, see TimeTag2Sec).
    tt = TimeTag2Sec(RFData(1:2, R.G.rcv_cols{1}(1), 1));
end
