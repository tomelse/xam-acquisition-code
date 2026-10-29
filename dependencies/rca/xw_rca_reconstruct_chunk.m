function IQ = xw_rca_reconstruct_chunk(R, RFData, k)
    % IQ = xw_rca_reconstruct_chunk(R, RFData, k)
    %   Reconstruct the rays of chunk k (R.chunks(k)) of a frame of the RCA
    %   sequence, as soon as these rays have been transferred from the
    %   hardware. Each ray has 3 pulses: X (both half apertures), L and R
    %   (one half each). PW = bf(L) + bf(R), xBmode = bf(X) and
    %   xAM = bf(X - L - R), where the subtraction is done on the RF data, as
    %   in xw_reconstruct_rays.
    %
    %   Order of the acquisitions in a frame: for every ray, orientation 1
    %   first: X, L, R, each with all angles; within a pulse the angle varies
    %   fastest, each acquisition has Nz_RF samples. The receive elements are
    %   the columns R.G.rcv_cols{orientation} of the receive buffer.
    %
    %   RFData : [rows, channels] or [rows, channels, frames]; only the rows of
    %            the rays of this chunk are read
    %   IQ     : struct with the complex IQ images [depth, positions along the
    %            receive axis, rays in chunk, frames] of the modes in R.modes
    c = R.chunks(k);
    nA = R.P.num_angles; Nz_RF = R.BFC.Nz_RF;
    nF = size(RFData, 3);
    rows_per_ray = 3 * nA * Nz_RF;
    rows = (c.global_rays(1) - 1) * rows_per_ray + 1:c.global_rays(end) * rows_per_ray;
    cols = R.G.rcv_cols{c.orientation};
    nCh = numel(cols);
    nr = numel(c.rays);

    A = to_single_if_half(R, RFData(rows, cols, :), Nz_RF);
    A = reshape(A, nA * Nz_RF, 3, nr, nCh, nF); % [samples*angles, pulse, ray, channel, frame]
    pulse = @(p) stack_frames(reshape(A(:, p, :, :, :), nA * Nz_RF * nr, nCh, nF));
    X = pulse(1); L = pulse(2); Rr = pulse(3);

    bf = @(rf) reshape(R.beamform(c.BFC, rf, c.LUT_T, c.LUT_R), R.BFC.Nz, [], nr, nF);
    if ismember('PW', R.modes), IQ.PW = bf(Rr) + bf(L); end
    if ismember('xBmode', R.modes), IQ.xBmode = bf(X); end
    if ismember('xAM', R.modes), IQ.xAM = bf(X - L - Rr); end
end

function RF2 = stack_frames(RF3)
    % [rows, channels, frames] -> [rows*frames, channels], frame by frame
    [nrows, nchannels, nframes] = size(RF3);
    RF2 = reshape(permute(RF3, [1 3 2]), nrows * nframes, nchannels);
end

function RF = to_single_if_half(R, RF, Nz_RF)
    % half data: the bit patterns to single, times 256, and the two samples of the
    % hardware time tag of every acquisition set to 0 (see xw_reconstruct_rays).
    % int16 data is converted to single, the time tag samples are left as they are.
    if ~strcmp(R.rf_datatype, 'half')
        RF = single(RF);
        return
    end
    sz = size(RF);
    RF = 256 * xw_half2single(RF);
    first = reshape((0:size(RF, 1) / Nz_RF - 1) * Nz_RF + [1; 2], [], 1);
    RF = reshape(RF, sz(1), []);
    RF(first, :) = 0;
    RF = reshape(RF, sz);
end
