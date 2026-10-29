function LUT = xw_rca_compute_LUT(z_vector, P, param, G, Trans, TW)
    % LUT = xw_rca_compute_LUT(z_vector, P, param, G, Trans, TW)
    %   Delay tables of the RCA beamformer, in the same way as
    %   xw_beamform_compute_LUT for the linear array.
    %
    %   LUT.TX    : [Nz, rays, angles] transmit delay [s] along the transmit
    %               aperture (the same for both orientations)
    %   LUT.RX{o} : [Nz, Nx, receive elements] receive delay [s] from the
    %               output positions along the receive axis (P.out_axis{o}, in m)
    %               to the receive elements of orientation o. Zero outside the
    %               f-number. It includes the offsets of the transmit waveform
    %               and the lens.
    c = param.c_us;
    z = z_vector(:);

    % transmit: along the aperture (angle and half aperture per ray, from xw_setup_build_transmit)
    Da = permute(P.ray_half_aperture * param.p, [3 2 1]); % [1, rays, angles]
    ang = permute(P.ray_angle, [3 2 1]);
    LUT.TX = (Da .* sind(ang) + z .* cosd(ang)) / c;

    % receive: from the output position to the element, if within the f-number
    toffset = TW(1).peak / (Trans.frequency * 1e6) + 2 * Trans.lensCorrection * 1e-3 / c;
    LUT.RX = cell(1, 2);
    for o = 1:2
        LUT.RX{o} = xw_rca_rx_lut(z, P.out_axis{o}, G.rx_pos{o} * 1e-3, param.f, c, toffset);
    end
end
