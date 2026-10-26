function BFData = xw_reconstruct_frame(R, RFData)
    % BFData = xw_reconstruct_frame(R, RFData)
    %   Reconstruct the images of one frame of RF data, as in the live view.
    %   R comes from xw_reconstruct_setup.
    %
    %   RFData : int16 [rows, channels] (one frame of RcvData{1}), or
    %            [rows, channels, frames] to reconstruct several at once
    %   BFData : struct with the complex IQ images ([depth, rays, frames]) of
    %            the modes in R.modes ('PW', 'xBmode', 'xAM') and TimeTag [s]
    %            of the first frame
    %
    %   Each ray has 3 pulses: X (both half apertures), L and R (one half
    %   each). PW = bf(L) + bf(R), xBmode = bf(X) and xAM = bf(X - L - R),
    %   where the subtraction is done on the RF data.
    %
    %   Order of the acquisitions in a frame (R.layout, P.rf_layout):
    %   'ray-major'   : for every ray: X, L, R, each with all angles
    %   'pulse-major' : all rays of X, then all rays of L, then of R (data
    %                   recorded before the receive buffer was ray-major)
    %   Within a pulse the angle varies fastest, each acquisition has Nz_RF samples.
    %   Groups of rays can also be reconstructed one by one: xw_reconstruct_chunk.

    TimeTag = TimeTag2Sec(RFData(1:2, 1, 1));
    BFData = xw_reconstruct_rays(R, RFData, R.BFC, R.LUT, 1:R.P.num_rays);
    BFData.TimeTag = TimeTag;
end
