function S = xw_rca_setup_burst(P, Trans, G, num_frames, tx_offset, rcv_offset, delay_fn)
    % S = xw_rca_setup_burst(P, Trans, G, num_frames, tx_offset, rcv_offset, delay_fn)
    %   Sequence structures of the burst of the row-column array (RCA), the
    %   counterpart of xw_setup_burst: a focused (wide beam) transmit per ray,
    %   with 3 pulses per ray: the full aperture, with the odd elements off, with
    %   the even elements off. The aperture is P.burst_num_tx elements of one
    %   half of the array, focused in the plane of the aperture (the elements are
    %   long in the other direction), and the rays are all positions of the
    %   aperture. As in the xAM sequence the orientation 1 rays are received with
    %   the other half of the array, then the orientations exchanged. The three
    %   echoes of a ray are accumulated on the hardware (the 2nd and 3rd are
    %   subtracted), which gives the amplitude modulation (AM) signal. The
    %   frames are reconstructed on the host by xw_rca_burst_reconstruct_frame.
    %
    %   P            : parameters, uses the P.burst_* settings (see xAM_imaging_RCA.m)
    %   G            : xw_rca_geometry of the transducer
    %   num_frames   : number of frames of the burst
    %   tx_offset    : number of TX structures before the burst TX (the TX of the burst are appended)
    %   rcv_offset   : number of Receive structures before the burst Receive (idem)
    %   delay_fn     : function that returns the TX delays, default computeTXDelays (for tests)
    %
    %   S.TX, S.Receive   : structures to append to TX and Receive
    %   S.TW, S.TGC       : transmit waveform and TGC of the burst (to be TW(2) and TGC(2))
    %   S.num_rays        : rays per orientation
    %   S.rows_per_frame  : rows of a frame of the burst receive buffer
    %   S.ray_centers{o}  : centre of the aperture of every ray of orientation o [mm]
    %   S.delay_centre    : [2, rays] transmit delay [s] of the centre of the aperture
    %   S.tx_index(orientation, pulse, ray), S.rcv_index(orientation, pulse, ray, frame)
    %   S.first_receive   : index in the Receive array of the first burst acquisition
    if nargin < 7, delay_fn = @computeTXDelays; end
    s = P.scale_mm2wvl; % wavelengths per mm
    nh = G.num_half; N = Trans.numelements;
    pitch = Trans.spacingMm * s; % [wavelengths]
    end_wvl = P.burst_end_depth_mm * s;
    num_tx = P.burst_num_tx;
    nr = nh - num_tx + 1; % rays per orientation
    assert(nr >= 1, 'The burst aperture of %i elements does not fit a half of the transducer (%i elements)', num_tx, nh)
    num_pulses = 3; num_orientations = 2;
    S.num_rays = nr;

    % transmit: pulse 1 all elements of the aperture, 2 the even ones, 3 the odd ones
    TX = repmat(struct('waveform', 2, ...
        'Origin', [0.0, 0.0, 0.0], ...
        'focus', P.burst_focus_mm * s, ...
        'Steer', [0.0, 0.0], ...
        'Apod', zeros(1, N), ...
        'Delay', zeros(1, N)), 1, num_orientations * num_pulses * nr);
    S.tx_index = @(o, pulse, ray) tx_offset + (o - 1) * num_pulses * nr + (pulse - 1) * nr + ray;
    S.ray_centers = cell(1, 2);
    S.delay_centre = zeros(2, nr);
    for o = 1:num_orientations
        el = G.tx_elements{o}; % elements of this half of the array
        is_x_half = el(1) == 1; % elements along x: the focal point is given by its x, else by its y
        S.ray_centers{o} = zeros(1, nr);
        for n = 1:nr
            active = el(n:n + num_tx - 1);
            c_mm = mean(G.tx_pos{o}(n:n + num_tx - 1)); % centre of the aperture [mm]
            S.ray_centers{o}(n) = c_mm;
            k = S.tx_index(o, 1, n) - tx_offset;
            if is_x_half, TX(k).Origin = [c_mm * s, 0.0, 0.0]; else, TX(k).Origin = [0.0, c_mm * s, 0.0]; end
            TX(k).Apod(active) = 1.0;
            TX(k).Delay = delay_fn(TX(k));
            S.delay_centre(o, n) = max(TX(k).Delay(active)) / (Trans.frequency * 1e6); % [s]
            for pulse = 2:num_pulses % same delays and origin for all pulses
                kp = S.tx_index(o, pulse, n) - tx_offset;
                TX(kp).Origin = TX(k).Origin;
                TX(kp).Delay = TX(k).Delay;
                TX(kp).Apod = TX(k).Apod;
            end
            TX(S.tx_index(o, 2, n) - tx_offset).Apod(el(1:2:end)) = 0; % odd elements off
            TX(S.tx_index(o, 3, n) - tx_offset).Apod(el(2:2:end)) = 0; % even elements off
        end
    end
    S.TX = TX;

    S.TW = struct('type', 'parametric', 'Parameters', [P.transmit_frequency, 0.67, P.burst_tw_half_cycles, 1]);

    S.TGC = struct('CntrlPts', 1023 * ones(1, 8), 'rangeMax', end_wvl);
    if exist('computeTGCWaveform', 'file'), S.TGC.Waveform = computeTGCWaveform(S.TGC); end

    % receive: per frame, for each orientation the 3 pulses of every ray; the 2nd and 3rd acquisition
    % are accumulated (mode 1) with all channels inverted onto the first one, so each ray is stored once.
    % The acquisitions start at depth 0, as for the xAM images.
    max_acq_length = ceil(sqrt(end_wvl ^ 2 + ((nh - 1) * pitch) ^ 2)); % [wavelengths]
    per_frame = num_orientations * num_pulses * nr;
    Receive = repmat(struct('Apod', zeros(1, N), ...
        'startDepth', 0, ...
        'endDepth', max_acq_length, ...
        'TGC', 2, ...
        'bufnum', 2, ...
        'framenum', 1, ...
        'acqNum', 1, ...
        'sampleMode', 'NS200BW', ...
        'datatype', 'int16', ...
        'mode', 0, ...
        'callMediaFunc', 0), 1, per_frame * num_frames);
    S.rcv_index = @(o, pulse, ray, frame) rcv_offset + per_frame * (frame - 1) + (o - 1) * num_pulses * nr + (pulse - 1) * nr + ray;
    for frame = 1:num_frames
        Receive(S.rcv_index(1, 1, 1, frame) - rcv_offset).callMediaFunc = 1;
        for o = 1:num_orientations
            for pulse = 1:num_pulses
                for ray = 1:nr
                    idx = S.rcv_index(o, pulse, ray, frame) - rcv_offset;
                    Receive(idx).Apod(G.rx_elements{o}) = 1; % the orthogonal elements
                    if pulse > 1
                        Receive(idx).mode = 1; % accumulate
                        Receive(idx).Apod(G.rx_elements{o}) = -1; % subtract
                    end
                    Receive(idx).framenum = frame;
                    Receive(idx).acqNum = (o - 1) * nr + ray;
                end
            end
        end
    end
    S.Receive = Receive;
    S.first_receive = rcv_offset + 1;

    % Rows of a frame of the receive buffer: samples per acquisition, rounded up to 128 (as for the xAM
    % acquisitions), for all acquisitions. VSX makes an acquisition longer than the depth asked for by about
    % the length of the transmit pulse and the transmit delays (a 7 half cycle focused burst more than the
    % 1 half cycle xAM pulses), so this has a margin; the reconstruction uses the number of samples that
    % VSX gives (Receive.endSample), and the rows after the last acquisition are not used.
    max_delay = max(arrayfun(@(t) max(t.Delay), TX)); % [wavelengths]
    extra = P.burst_tw_half_cycles / 2 + max_delay + 10; % [wavelengths]
    S.rows_per_frame = num_orientations * nr * ceil((max_acq_length + extra) * 2 * 4 * P.demod_ratio / 128) * 128;
    S.max_acq_length_mm = max_acq_length / s;
end
