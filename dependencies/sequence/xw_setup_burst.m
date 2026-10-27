function S = xw_setup_burst(P, Trans, num_frames, tx_offset, rcv_offset)
    % S = xw_setup_burst(P, Trans, num_frames, tx_offset, rcv_offset)
    %   Sequence structures of the burst: a focused (wide beam) transmit per ray, as in
    %   the BURST_L22_14v_VSRyLnAM_SyncBurst script, with 3 pulses per ray: the full
    %   aperture, with the odd elements off, with the even elements off. The three echoes
    %   are accumulated on the hardware (the 2nd and 3rd are subtracted), which gives the
    %   amplitude modulation (AM) signal, and are reconstructed per ray by the Verasonics
    %   reconstruction (Recon, ReconInfo and PData, replaceIntensity).
    %
    %   P            : parameters, uses the P.burst_* settings (see xAM_imaging.m)
    %   num_frames   : number of frames of the burst
    %   tx_offset    : number of TX structures before the burst TX (the TX of the burst are appended)
    %   rcv_offset   : number of Receive structures before the burst Receive (idem)
    %
    %   S.TX, S.Receive   : structures to append to TX and Receive
    %   S.TW, S.TGC       : transmit waveform and TGC of the burst (to be TW(2) and TGC(2))
    %   S.PData, S.Recon, S.ReconInfo : reconstruction
    %   S.num_rays, S.rows_per_frame, S.x_axis, S.z_axis [mm]
    %   S.tx_index(pulse, ray)       : index of the TX in the TX array
    %   S.rcv_index(pulse, ray, frame): index of the Receive in the Receive array
    %   S.recon_final(k), S.recon_preview, S.recon_request : numbers of the Recon structures:
    %       the reconstruction of frame k, of the latest frame, and a fast one ray reconstruction
    %       of the latest frame (see xAM_imaging.m)
    s = P.scale_mm2wvl; % wavelengths per mm
    num_el = Trans.numelements;
    pitch = Trans.spacingMm * s; % [wavelengths]
    start_wvl = P.burst_start_depth_mm * s;
    end_wvl = P.burst_end_depth_mm * s;
    num_tx = P.burst_num_tx;
    nr = num_el - num_tx + 1; % rays
    half_ap = (num_tx - rem(num_tx, 2)) / 2; % active elements in half the transmit aperture
    offset = floor(num_el / 2) - floor(nr / 2) - half_ap;
    num_pulses = 3;
    S.num_rays = nr;

    % transmit: pulse 1 all elements of the aperture, 2 the even ones, 3 the odd ones
    TX = repmat(struct('waveform', 2, ...
        'Origin', [0.0, 0.0, 0.0], ...
        'focus', P.burst_focus_mm * s, ...
        'Steer', [0.0, 0.0], ...
        'Apod', zeros(1, num_el), ...
        'Delay', zeros(1, num_el)), 1, num_pulses * nr);
    x_center = zeros(1, nr); % center of the aperture of each ray [wavelengths]
    for n = 1:nr
        lft = n + offset;
        rt = n + 2 * half_ap - 1 + rem(num_tx, 2) + offset;
        assert(lft >= 1 && rt <= num_el, 'The burst aperture of %i elements does not fit the transducer', num_tx)
        x_center(n) = mean(Trans.ElementPos(lft:rt, 1)) * s;
        TX(n).Origin = [x_center(n), 0.0, 0.0];
        TX(n).Apod(lft:rt) = 1.0;
        TX(n + nr).Apod = TX(n).Apod;
        TX(n + nr).Apod(1:2:end) = 0; % odd elements off
        TX(n + 2 * nr).Apod = TX(n).Apod;
        TX(n + 2 * nr).Apod(2:2:end) = 0; % even elements off
        TX(n).Delay = computeTXDelays(TX(n));
        for pulse = 2:num_pulses % same delays and origin for all pulses
            TX(n + (pulse - 1) * nr).Origin = TX(n).Origin;
            TX(n + (pulse - 1) * nr).Delay = TX(n).Delay;
        end
    end
    S.TX = TX;
    S.tx_index = @(pulse, ray) tx_offset + (pulse - 1) * nr + ray;

    S.TW = struct('type', 'parametric', 'Parameters', [P.transmit_frequency, 0.67, P.burst_tw_half_cycles, 1]);

    S.TGC = struct('CntrlPts', 1023 * ones(1, 8), 'rangeMax', end_wvl);
    S.TGC.Waveform = computeTGCWaveform(S.TGC);

    % receive: per frame, the 3 pulses of every ray in turn; the 2nd and 3rd acquisition are
    % accumulated (mode 1) with all channels inverted onto the first one, so each ray is stored once
    max_acq_length = ceil(sqrt(end_wvl ^ 2 + ((num_el - 1) * pitch) ^ 2)); % [wavelengths]
    Receive = repmat(struct('Apod', ones(1, num_el), ...
        'startDepth', start_wvl, ...
        'endDepth', max_acq_length, ...
        'TGC', 2, ...
        'bufnum', 2, ...
        'framenum', 1, ...
        'acqNum', 1, ...
        'sampleMode', 'NS200BW', ...
        'datatype', 'int16', ...
        'mode', 0, ...
        'callMediaFunc', 0), 1, num_pulses * nr * num_frames);
    for frame = 1:num_frames
        Receive(num_pulses * nr * (frame - 1) + 1).callMediaFunc = 1;
        for pulse = 1:num_pulses
            for ray = 1:nr
                idx = num_pulses * nr * (frame - 1) + (pulse - 1) * nr + ray;
                if pulse > 1
                    Receive(idx).mode = 1; % accumulate
                    Receive(idx).Apod(:) = -1; % subtract
                end
                Receive(idx).framenum = frame;
                Receive(idx).acqNum = ray;
            end
        end
    end
    S.Receive = Receive;
    S.rcv_index = @(pulse, ray, frame) rcv_offset + num_pulses * nr * (frame - 1) + (pulse - 1) * nr + ray;

    % samples per acquisition, rounded up to 128 (as for the xAM acquisitions)
    demod_frequency = Trans.frequency;
    S.rows_per_frame = nr * ceil(max_acq_length * 2 * 4 * demod_frequency / Trans.frequency / 128) * 128;

    % image: one column pair (half pitch) per ray, 0.5 wavelength in depth
    PData.PDelta = [pitch / 2, 0, 0.5];
    PData.Size(1) = ceil((end_wvl - start_wvl) / PData.PDelta(3));
    PData.Size(2) = ceil(nr * pitch / PData.PDelta(1));
    PData.Size(3) = 1;
    PData.Origin = [-pitch * nr / 2, 0, start_wvl]; % x, y, z of the upper left corner
    PData.Region = repmat(struct('Shape', struct( ...
        'Name', 'Rectangle', ...
        'Position', [0, 0, start_wvl], ...
        'width', pitch, ...
        'height', end_wvl - start_wvl)), 1, nr);
    for n = 1:nr
        PData.Region(n).Shape.Position(1) = x_center(n);
    end
    PData.Region = computeRegions(PData);
    S.PData = PData;
    S.x_axis = (PData.Origin(1) + (0:PData.Size(2) - 1) * PData.PDelta(1)) / s; % [mm]
    S.z_axis = (PData.Origin(3) + (0:PData.Size(1) - 1) * PData.PDelta(3)) / s; % [mm]

    % reconstruction. Recon 1..num_frames: frame k of the burst. Then the preview of the latest
    % frame (all rays), and a reconstruction of one ray of the latest frame, which only serves to
    % ask for the latest frame (see xAM_imaging.m)
    S.recon_preview = num_frames + 1;
    S.recon_request = num_frames + 2;
    S.recon_final = @(k) k;
    Recon = repmat(struct('senscutoff', 0.6, ...
        'pdatanum', 1, ...
        'rcvBufFrame', -1, ...
        'IntBufDest', [0, 0], ...
        'ImgBufDest', [2, -1], ...
        'RINums', 1:nr), 1, num_frames + 2);
    ReconInfo = repmat(struct('mode', 'replaceIntensity', ...
        'txnum', 1, ...
        'rcvnum', 1, ...
        'regionnum', 0), 1, nr * (num_frames + 1) + 1);
    for k = 1:num_frames + 1 % ReconInfo of recon k: (k - 1) * nr + (1:nr); k = num_frames + 1: preview
        for ray = 1:nr
            ri = (k - 1) * nr + ray;
            ReconInfo(ri).txnum = S.tx_index(1, ray);
            ReconInfo(ri).rcvnum = S.rcv_index(1, ray, 1);
            ReconInfo(ri).regionnum = ray;
        end
        Recon(k).RINums = (k - 1) * nr + (1:nr);
        if k <= num_frames
            Recon(k).rcvBufFrame = k;
            Recon(k).ImgBufDest = [1, k];
        end
    end
    ri = nr * (num_frames + 1) + 1; % the one ray reconstruction
    ReconInfo(ri).txnum = S.tx_index(1, 1);
    ReconInfo(ri).rcvnum = S.rcv_index(1, 1, 1);
    ReconInfo(ri).regionnum = 1;
    Recon(S.recon_request).RINums = ri;
    S.Recon = Recon;
    S.ReconInfo = ReconInfo;
end
