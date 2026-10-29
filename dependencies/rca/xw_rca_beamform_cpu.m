function BFIQ = xw_rca_beamform_cpu(BFC, RF, LUT_T, LUT_R)
    % BFIQ = xw_rca_beamform_cpu(BFC, RF, LUT_T, LUT_R)
    %   Beamformer of the row-column array (RCA): MATLAB reference, also used on
    %   the GPU when the inputs are gpuArrays (see xw_rca_beamform_gpu).
    %   Same delay-and-sum as xw_beamform_cpu (IQ demodulation, 9-tap Hann
    %   low-pass, linear interpolation), but every ray gives a plane, not a
    %   line: the transmit (an xWave from one orientation of elements) is
    %   localised in the direction of its aperture, the receive elements are
    %   orthogonal to it and resolve the other direction.
    %
    %   RF    : [Nz_RF*NAngles*NRays*NFrames, nCh] int16 or single, the
    %           acquisitions of the receive elements, ordered angle-fastest,
    %           then ray; frames stacked along the rows
    %   LUT_T : [Nz, NRays, NAngles] transmit delay [s]
    %   LUT_R : [Nz, Nx, nCh] receive delay [s] to the output positions along
    %           the receive axis, the same for all rays (0 = element outside
    %           the f-number)
    %   BFIQ  : [Nz, Nx, NRays, NFrames] complex single
    rows_per_frame = BFC.Nz_RF * BFC.NAngles * BFC.NRays;
    nF = size(RF, 1) / rows_per_frame;
    assert(nF == round(nF), 'xw_rca_beamform_cpu: RF rows (%i) not a multiple of Nz_RF*NAngles*NRays (%i)', size(RF, 1), rows_per_frame);

    Nz = size(LUT_T, 1); Nx = size(LUT_R, 2);
    BFIQ = complex(zeros(Nz, Nx, BFC.NRays, nF, 'single'));
    if isa(LUT_R, 'gpuArray'), BFIQ = gpuArray(BFIQ); end
    for f = 1:nF
        rf = RF((f - 1) * rows_per_frame + (1:rows_per_frame), :);
        BFIQ(:, :, :, f) = beamform_frame(BFC, rf, LUT_T, LUT_R);
    end
end

function BFIQ = beamform_frame(BFC, RF, LUT_T, LUT_R)
    Fs = BFC.decimSampleRate; fd = BFC.demodFrequency;
    Nz_RF = BFC.Nz_RF; nA = BFC.NAngles; nR = BFC.NRays;
    nCh = size(RF, 2); [Nz, Nx, ~] = size(LUT_R);

    % IQ demodulation: mix down by fd, low-pass to remove the 2*fd image
    RF = reshape(single(RF), Nz_RF, nA * nR * nCh);
    n = single((0:Nz_RF - 1).');
    if isa(LUT_R, 'gpuArray'), RF = gpuArray(RF); n = gpuArray(n); end
    bb = RF .* exp(-1i * 2 * pi * fd / Fs * n);
    h = single(hann(9)); h = 2 * h / sum(h);
    bb = conv2(bb, h, 'same'); % [Nz_RF, nA*nR*nCh]

    mask = LUT_R > 1e-15; % [Nz, Nx, nCh]
    % offset of the channel in bb: linear indices exceed 2^24, so they must be double, not single
    ch_off = double(reshape(0:nCh - 1, 1, 1, nCh)) * Nz_RF * nA * nR;
    BFIQ = complex(zeros(Nz, Nx, nR, 'single'));
    if isa(LUT_R, 'gpuArray'), BFIQ = gpuArray(BFIQ); ch_off = gpuArray(ch_off); end
    for r = 1:nR
        for a = 1:nA
            t = LUT_T(:, r, a) + LUT_R; % [Nz, Nx, nCh] two-way travel time
            s = t * Fs + 1;
            s0 = floor(s); w = s - s0;
            valid = mask & s0 >= 1 & s0 < Nz_RF;
            s0(~valid) = 1; w(~valid) = 0;
            idx = double(s0) + ((r - 1) * nA + a - 1) * Nz_RF + ch_off;
            v = ((1 - w) .* bb(idx) + w .* bb(idx + 1)) .* exp(1i * 2 * pi * fd * t) .* valid;
            BFIQ(:, :, r) = BFIQ(:, :, r) + sum(v, 3);
        end
    end
end
