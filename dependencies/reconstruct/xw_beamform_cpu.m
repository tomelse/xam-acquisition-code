function BFIQ = xw_beamform_cpu(BFC, RF, LUT_T, LUT_R)
    % BFIQ = xw_beamform_cpu(BFC, RF, LUT_T, LUT_R)
    %   MATLAB stand-in for the compiled beamformer MLBFXWave (XW mode, IQ
    %   demodulation, linear interpolation), for platforms without a compiled
    %   build. Same inputs and output as MLBFXWave. Slow (~200 ms per image on a
    %   16-core CPU) and not validated against MLBFXWave.
    %
    %   Enable with P.use_cpu_beamformer = true, or XAM_CPU_BEAMFORMER=1 in the
    %   environment (see xAM_imaging.m).
    %
    %   RF    : [Nz_RF*NAngles*NRays*NFrames, nCh] int16, acquisitions ordered
    %           angle-fastest, then ray; frames stacked along the rows
    %   LUT_T : [Nz, NRays, NAngles] transmit delay [s]
    %   LUT_R : [Nz, NRays, nCh] receive delay [s] (0 = element outside f-number)
    %   BFIQ  : [Nz, NRays, NFrames] complex single
    rows_per_frame = BFC.Nz_RF * BFC.NAngles * BFC.NRays;
    nF = size(RF, 1) / rows_per_frame;
    assert(nF == round(nF), 'xw_beamform_cpu: RF rows (%i) not a multiple of Nz_RF*NAngles*NRays (%i)', size(RF, 1), rows_per_frame);

    BFIQ = complex(zeros(size(LUT_T, 1), BFC.NRays, nF, 'single'));
    for f = 1:nF
        BFIQ(:, :, f) = beamform_frame(BFC, RF((f - 1) * rows_per_frame + (1:rows_per_frame), :), LUT_T, LUT_R);
    end
end

function BFIQ = beamform_frame(BFC, RF, LUT_T, LUT_R)
    Fs = BFC.decimSampleRate; fd = BFC.demodFrequency;
    Nz_RF = BFC.Nz_RF; nA = BFC.NAngles; nR = BFC.NRays;
    nCh = size(RF, 2); Nz = size(LUT_T, 1);

    % IQ demodulation: mix down by fd, low-pass to remove the 2*fd image
    RF = reshape(single(RF), Nz_RF, nA * nR * nCh);
    n = single((0:Nz_RF - 1).');
    bb = RF .* exp(-1i * 2 * pi * fd / Fs * n);
    h = single(hann(9)); h = 2 * h / sum(h);
    bb = conv2(bb, h, 'same'); % [Nz_RF, nA*nR*nCh]

    % delay-and-sum over elements, for every depth and ray at once.
    % Linear indices exceed 2^24, so they must be double, not single.
    R = reshape(LUT_R, Nz, nR, nCh);
    mask = R > 1e-15;
    off = double(reshape(0:nR - 1, 1, nR)) * Nz_RF * nA ...
        + double(reshape(0:nCh - 1, 1, 1, nCh)) * Nz_RF * nA * nR;
    BFIQ = complex(zeros(Nz, nR, 'single'));
    for a = 1:nA
        t = LUT_T(:, :, a) + R; % [Nz, nR, nCh] two-way travel time
        s = t * Fs + 1;
        s0 = floor(s); w = s - s0;
        valid = mask & s0 >= 1 & s0 < Nz_RF;
        s0(~valid) = 1; w(~valid) = 0;
        idx = double(s0) + (a - 1) * Nz_RF + off;
        v = ((1 - w) .* bb(idx) + w .* bb(idx + 1)) .* exp(1i * 2 * pi * fd * t) .* valid;
        BFIQ = BFIQ + sum(v, 3);
    end
end
