function V = xw_rca_burst_reconstruct_frame(Rb, RF)
    % V = xw_rca_burst_reconstruct_frame(Rb, RF)
    %   Reconstruct one frame of a burst of the RCA: the envelope of the AM
    %   signal as a volume [depth, second axis, first axis] (Rb.z_axis,
    %   Rb.axis_second, Rb.axis_first), the two orientations combined as for the
    %   xAM images (xw_rca_combine_orientations). Linear intensity, to be
    %   subtracted as it is.
    %
    %   RF : [rows, N/2] int16: the rows of the frame of the burst receive
    %        buffer (orientation 1, then 2; rays in turn, Nz_RF samples each;
    %        rows after the last acquisition are not used)
    %        with the columns of the receive elements of the orientation of the
    %        rows (xw_rca_burst_capture)
    nr = Rb.num_rays; Nz_RF = Rb.BFC.Nz_RF;
    assert(size(RF, 1) >= 2 * nr * Nz_RF, 'xw_rca:burstrows', ...
        'A frame of the burst has %i rows, at least %i expected (2 orientations x %i rays x %i samples)', size(RF, 1), 2 * nr * Nz_RF, nr, Nz_RF);
    part = cell(1, 2);
    for o = 1:2
        rows = (o - 1) * nr * Nz_RF + (1:nr * Nz_RF);
        part{o}.xAM = reshape(Rb.beamform(Rb.BFC, RF(rows, :), Rb.LUT_T{o}, Rb.LUT_R{o}), Rb.BFC.Nz, [], nr);
    end
    BF = xw_rca_combine_orientations(Rb, part);
    V = BF.xAM;
end
