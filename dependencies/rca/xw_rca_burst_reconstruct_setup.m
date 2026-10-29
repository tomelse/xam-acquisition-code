function Rb = xw_rca_burst_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    % Rb = xw_rca_burst_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    %   Image grid, delay tables and beamformer for the frames of a burst of
    %   the RCA (see xw_rca_setup_burst), reconstructed by
    %   xw_rca_burst_reconstruct_frame. Needs P.burst_* , P.burst_ray_centers{o}
    %   [mm] and P.burst_delay_centre (from xw_rca_setup_burst), P.burst_first_receive
    %   (the first burst acquisition in Receive) and TW(2).
    %
    %   The transmit is focused in the plane of the aperture, so the pressure at
    %   depth z on the axis of a ray arrives at the delay of the centre of the
    %   aperture + z/c, before and after the focus. As in the xAM images, the
    %   output positions along the receive axis of one orientation are the ray
    %   centres of the other.
    if nargin < 5 || isempty(beamformer), beamformer = 'auto'; end
    G = xw_rca_geometry(Trans, P.first_orientation);
    c = P.speed_of_sound;
    lambda = P.scale_wvl2mm * 1e-3;
    f_number = 1.28;
    if isfield(P, 'fNumber'), f_number = P.fNumber; end

    z = P.burst_start_depth_mm * 1e-3:lambda / 2:P.burst_end_depth_mm * 1e-3; % [m]
    nr = size(P.burst_delay_centre, 2);
    ray_axis = {P.burst_ray_centers{1}(:)' * 1e-3, P.burst_ray_centers{2}(:)' * 1e-3}; % [m]
    out_axis = {ray_axis{2}, ray_axis{1}};
    toffset = TW(2).peak / (Trans.frequency * 1e6) + 2 * Trans.lensCorrection * 1e-3 / c;

    Rb.G = G;
    Rb.z_axis = z;
    Rb.axis_first = ray_axis{1};
    Rb.axis_second = ray_axis{2};
    Rb.modes = {'xAM'};
    Rb.LUT_T = cell(1, 2); Rb.LUT_R = cell(1, 2);
    for o = 1:2
        Rb.LUT_T{o} = single(P.burst_delay_centre(o, :) + z(:) / c); % [Nz, rays]
        Rb.LUT_R{o} = single(xw_rca_rx_lut(z, out_axis{o}, G.rx_pos{o} * 1e-3, f_number, c, toffset));
    end

    BFC.Nz_RF = Receive(P.burst_first_receive).endSample; % samples per acquisition
    BFC.NAngles = 1;
    BFC.NRays = nr;
    BFC.decimSampleRate = Receive(1).decimSampleRate * 1e6;
    BFC.demodFrequency = Receive(1).demodFrequency * 1e6;
    BFC.Nz = numel(z);
    BFC.fNumber = f_number;
    Rb.BFC = BFC;
    Rb.num_rays = nr;

    [Rb.beamform, Rb.beamformer] = xw_rca_choose_beamformer(P, beamformer);
    if strcmp(Rb.beamformer, 'gpu')
        Rb.LUT_T = cellfun(@gpuArray, Rb.LUT_T, 'UniformOutput', false);
        Rb.LUT_R = cellfun(@gpuArray, Rb.LUT_R, 'UniformOutput', false);
    end
end
