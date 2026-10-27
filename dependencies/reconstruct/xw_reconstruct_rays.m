function IQ = xw_reconstruct_rays(R, RFData, BFC, LUT, rays)
    % IQ = xw_reconstruct_rays(R, RFData, BFC, LUT, rays)
    %   Shared by xw_reconstruct_frame and xw_reconstruct_chunk: splits the
    %   acquisitions of the given rays into the X, L and R pulses and
    %   beamforms the images of R.modes with the tables of these rays.
    if ~isfield(R, 'rf_datatype'), R.rf_datatype = 'int16'; end
    nA = R.P.num_angles; Nz_RF = R.BFC.Nz_RF; nR = R.P.num_rays;
    nF = size(RFData, 3);
    switch R.layout
        case 'ray-major'
            % [samples*angles, pulse, ray, channel, frame]: take the rays and split the pulses
            rows_per_ray = 3 * nA * Nz_RF;
            A = RFData((rays(1) - 1) * rows_per_ray + 1:rays(end) * rows_per_ray, :, :);
            A = to_single_if_half(R, A);
            A = reshape(A, nA * Nz_RF, 3, numel(rays), size(RFData, 2), nF);
            pulse = @(p) reshape(A(:, p, :, :, :), nA * Nz_RF * numel(rays), size(RFData, 2), nF);
        case 'pulse-major'
            ntot = Nz_RF * nR * nA;
            ind = @(p) ((p - 1) * ntot + (1:ntot));
            RFData = to_single_if_half(R, RFData);
            pulse = @(p) RFData(ind(p), :, :);
            assert(isequal(rays, 1:nR), 'chunks need the ray-major layout');
        otherwise
            error('xw_reconstruct:layout', 'Unknown receive buffer layout ''%s''', R.layout);
    end
    RF.XW = pulse(1);
    RF.PW_L = pulse(2);
    RF.PW_R = pulse(3);
    if nF > 1 % several frames: stack them along the rows
        RF = structfun(@stack_frames, RF, 'UniformOutput', false);
    end
    RF.XW_AM = RF.XW - RF.PW_R - RF.PW_L; % nonlinear signal

    bf = @(rf) R.beamform(BFC, rf, LUT.TX, LUT.RX);
    if ismember('PW', R.modes)
        IQ.PW = bf(RF.PW_R) + bf(RF.PW_L); % compound of the two plane waves
    end
    if ismember('xBmode', R.modes), IQ.xBmode = bf(RF.XW); end
    if ismember('xAM', R.modes), IQ.xAM = bf(RF.XW_AM); end
end

function RF2 = stack_frames(RF3)
    % [rows, channels, frames] -> [rows*frames, channels], frame by frame
    [nrows, nchannels, nframes] = size(RF3);
    RF2 = reshape(permute(RF3, [1 3 2]), nrows * nframes, nchannels);
end

function RF = to_single_if_half(R, RF)
    % half data: convert the bit patterns to single, times 256: the system divides
    % the 22 bit filter output by 256 before storing it as half (Receive.datatype
    % in the Sequence Programming Manual), so this gives the same scale as int16
    % data. The first two samples of every acquisition hold the hardware time
    % tag, not data: set them to 0 (with int16 data they are left as they are,
    % above the imaged depth).
    if ~strcmp(R.rf_datatype, 'half'), return, end
    Nz_RF = R.BFC.Nz_RF;
    RF = 256 * xw_half2single(RF);
    first = reshape((0:size(RF, 1) / Nz_RF - 1) * Nz_RF + [1; 2], [], 1); % samples 1 and 2 of every acquisition
    RF(first, 1, :) = 0;
end
