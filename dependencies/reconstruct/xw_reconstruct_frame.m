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
    %   Each frame holds 3 blocks of acquisitions: X (both half apertures), L
    %   and R (one half each). PW = bf(L) + bf(R), xBmode = bf(X) and
    %   xAM = bf(X - L - R), where the subtraction is done on the RF data.

    P = R.P;
    TimeTag = TimeTag2Sec(RFData(1:2, 1, 1));

    % split the frame into the X, L and R blocks
    ntot = R.BFC.Nz_RF * P.num_rays * P.num_angles;
    inds = 1:ntot;
    RF.XW = RFData(inds + 0 * ntot, :, :);
    RF.PW_L = RFData(inds + 1 * ntot, :, :);
    RF.PW_R = RFData(inds + 2 * ntot, :, :);
    if size(RFData, 3) > 1 % several frames: stack them along the rows
        RF = structfun(@stack_frames, RF, 'UniformOutput', false);
    end
    RF.XW_AM = RF.XW - RF.PW_R - RF.PW_L; % nonlinear signal

    bf = @(rf) R.beamform(R.BFC, rf, R.LUT.TX, R.LUT.RX);
    if ismember('PW', R.modes)
        BFData.PW = bf(RF.PW_R) + bf(RF.PW_L); % compound of the two plane waves
    end
    if ismember('xBmode', R.modes), BFData.xBmode = bf(RF.XW); end
    if ismember('xAM', R.modes), BFData.xAM = bf(RF.XW_AM); end
    BFData.TimeTag = TimeTag;
end

function RF2 = stack_frames(RF3)
    % [rows, channels, frames] -> [rows*frames, channels], frame by frame
    [nrows, nchannels, nframes] = size(RF3);
    RF2 = reshape(permute(RF3, [1 3 2]), nrows * nframes, nchannels);
end
