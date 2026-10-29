function R = xw_rca_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    % R = xw_rca_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    %   Prepare image reconstruction of the row-column array (RCA) sequence of
    %   xAM_imaging_RCA.m: image grid, delay tables and beamformer. Used by the
    %   live view (xw_rca_beamform_run) and for offline reconstruction, as
    %   xw_reconstruct_setup is for the linear array. Reconstruct frames with
    %   xw_rca_reconstruct_frame(R, RFData).
    %
    %   P, Receive, Trans, TW : sequence structs, as in the base workspace while
    %                           running, or from acq_parameters.mat
    %   beamformer            : 'auto' (default: as the live view), 'gpu' or 'cpu'
    %
    %   The image is a volume [depth, dim 2, dim 3]. Dimension 3 is the axis of
    %   the elements that transmit first (the position of the ray in the first
    %   orientation), dimension 2 the axis of the elements that transmit second.
    %   R has fields P (with z_axis, axis_first, axis_second [m]), modes, G
    %   (xw_rca_geometry), LUT, BFC, beamform, beamformer, rf_datatype and
    %   chunks (rays that are reconstructed together, see xw_rca_reconstruct_chunk).
    if nargin < 5 || isempty(beamformer), beamformer = 'auto'; end

    G = xw_rca_geometry(Trans, P.first_orientation);

    param.p = Trans.spacingMm * 1e-3; % element pitch [m]
    param.lambda = P.scale_wvl2mm * 1e-3;
    param.c_us = P.speed_of_sound;
    param.Fs = Receive(1).decimSampleRate * 1e6; % [Hz]
    param.Fc = Receive(1).demodFrequency * 1e6; % [Hz]
    param.f = 1.28; % f-number
    if isfield(P, 'fNumber'), param.f = P.fNumber; end

    R.modes = {'PW', 'xBmode', 'xAM'};
    if isfield(P, 'beamform_image_modes'), R.modes = P.beamform_image_modes; end

    % image grid: a row every half wavelength in depth, the rays of each
    % orientation along its axis; the output positions of one orientation are
    % the ray positions of the other, so both give the same volume
    z_vector = P.image_start_depth_mm * 1e-3:param.lambda / 2:P.image_end_depth_mm * 1e-3; % [m]
    ray_axis = cell(1, 2);
    for o = 1:2
        ray_axis{o} = interp1(1:G.num_half, G.tx_pos{o}, P.ray_positions) * 1e-3; % [m]
    end
    P.z_axis = z_vector;
    P.axis_first = ray_axis{1};
    P.axis_second = ray_axis{2};
    P.out_axis = {ray_axis{2}, ray_axis{1}};
    R.P = P;
    R.G = G;

    R.LUT = xw_rca_compute_LUT(z_vector, P, param, G, Trans, TW);
    R.LUT.TX = single(R.LUT.TX);
    R.LUT.RX = cellfun(@single, R.LUT.RX, 'UniformOutput', false);

    BFC.Nz_RF = Receive(1).endSample; % samples per acquisition
    BFC.NAngles = P.num_angles;
    BFC.NRays = P.num_rays;
    BFC.decimSampleRate = param.Fs;
    BFC.demodFrequency = param.Fc;
    BFC.Nz = numel(z_vector);
    BFC.fNumber = param.f;
    R.BFC = BFC;

    R.rf_datatype = 'int16';
    if isfield(Receive, 'datatype') && ~isempty(Receive(1).datatype), R.rf_datatype = Receive(1).datatype; end

    if strcmp(beamformer, 'auto')
        if isfield(P, 'use_cpu_beamformer') && P.use_cpu_beamformer
            beamformer = 'cpu';
        else
            beamformer = 'gpu';
        end
    end
    switch beamformer
        case 'cpu'
            R.beamform = @xw_rca_beamform_cpu;
            fprintf('Using the CPU beamformer (xw_rca_beamform_cpu)\n');
        case 'gpu'
            fprintf('Starting the GPU (the first time on a new GPU, MATLAB compiles its GPU libraries, which can take minutes)\n');
            [gpu_ok, gpu_msg] = xw_beamform_gpu_available();
            if ~gpu_ok
                error('xw_beamform:nogpu', ['The GPU beamformer cannot run: %s.\n' ...
                    'To use the slow CPU beamformer instead, set P.use_cpu_beamformer = true or run with --cpu-beamformer.'], gpu_msg);
            end
            R.beamform = @xw_rca_beamform_gpu;
            fprintf('Using the GPU beamformer (xw_rca_beamform_gpu) on %s\n', gpu_msg);
        otherwise
            error('xw_rca:beamformer', 'Unknown beamformer ''%s'': use ''auto'', ''gpu'' or ''cpu''', beamformer);
    end
    R.beamformer = beamformer;

    % groups of rays for xw_rca_reconstruct_chunk, with their delay tables (kept on the GPU)
    plan = xw_rca_chunk_plan(P.num_rays, P.num_chunks);
    R.chunks = struct('orientation', {}, 'rays', {}, 'global_rays', {}, 'BFC', {}, 'LUT_T', {}, 'LUT_R', {});
    for k = 1:numel(plan)
        c = plan(k);
        c.BFC = R.BFC;
        c.BFC.NRays = numel(c.rays);
        c.LUT_T = R.LUT.TX(:, c.rays, :);
        c.LUT_R = R.LUT.RX{c.orientation};
        if strcmp(beamformer, 'gpu')
            c.LUT_T = gpuArray(c.LUT_T);
            c.LUT_R = gpuArray(c.LUT_R);
        end
        R.chunks(k) = c;
    end
end
