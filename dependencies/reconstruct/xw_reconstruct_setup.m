function R = xw_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    % R = xw_reconstruct_setup(P, Receive, Trans, TW, beamformer)
    %   Prepare image reconstruction for a sequence: image grid, delay lookup
    %   tables and beamformer. Used by the live view (xw_beamform_run) and for
    %   offline reconstruction (examples/reconstruct_rf.m), so both give the
    %   same images. Reconstruct frames with xw_reconstruct_frame(R, RFData).
    %
    %   P, Receive, Trans, TW : sequence structs, as in the base workspace while
    %                           running, or from acq_parameters.mat / a snapshot
    %   beamformer            : 'auto' (default: as the live view), 'gpu' or 'cpu'
    %
    %   R has fields P (with x_axis, z_axis), modes, LUT, BFC, beamform (function
    %   handle), beamformer (name), layout (order of the acquisitions in the
    %   receive buffer, see xw_reconstruct_frame), rf_datatype ('int16' or 'half')
    %   and chunks (rays that can be
    %   reconstructed separately, see xw_reconstruct_chunk).
    if nargin < 5 || isempty(beamformer)
        beamformer = 'auto';
    end

    % reconstruction parameters
    param.p = Trans.spacingMm * 1e-3; % element pitch [m]
    param.lambda = P.scale_wvl2mm * 1e-3; % 1 wavelength [m]
    param.c_us = P.speed_of_sound; % [m/s]
    param.Fs = Receive(1).decimSampleRate * 1e6; % [Hz]
    param.Fc = Receive(1).demodFrequency * 1e6; % [Hz]
    param.f = 1.28; % f-number
    if isfield(P, 'fNumber'), param.f = P.fNumber; end

    % images to reconstruct: 'PW' (B-mode, L + R), 'xBmode' (X), 'xAM' (X - L - R)
    R.modes = {'PW', 'xBmode', 'xAM'};
    if isfield(P, 'beamform_image_modes'), R.modes = P.beamform_image_modes; end

    % image grid: one column per ray, a row every half wavelength
    z_vector = P.image_start_depth_mm * 1e-3:param.lambda / 2:P.image_end_depth_mm * 1e-3; % [m]
    P.x_axis = interp1(1:Trans.numelements, Trans.ElementPos(:, 1), P.ray_positions) * 1e-3; % [m]
    P.z_axis = z_vector;
    R.P = P;

    % delay lookup tables
    R.LUT = xw_beamform_compute_LUT(R.modes, z_vector, P, param, Trans, TW);
    R.LUT = structfun(@single, R.LUT, 'UniformOutput', false);

    % beamformer configuration (interface of MLBFXWave)
    Nz_RF = Receive(1).endSample; % samples per acquisition
    BFC.XPiezo = Trans.ElementPos(:, 1) * 1e-3; % [m]
    BFC.ZPiezo = 0 * BFC.XPiezo;
    BFC.Origin = [P.z_axis(1); P.x_axis(1)];
    BFC.ScaleZ = P.z_axis(2) - P.z_axis(1);
    BFC.ScaleX = P.x_axis(2) - P.x_axis(1);
    BFC.Nx = numel(P.x_axis);
    BFC.Nz = numel(P.z_axis);
    BFC.Nz_RF = Nz_RF;
    BFC.fNumber = param.f;
    BFC.NTx = P.num_angles;
    BFC.Angles = P.xwave_angles;
    BFC.NAngles = P.num_angles;
    BFC.NRays = P.num_rays;
    BFC.NFrames = 1;
    BFC.decimSampleRate = param.Fs;
    BFC.demodFrequency = param.Fc;
    BFC.speedOfSound = P.speed_of_sound;
    BFC.CorrectionForTW = 0; % already added to the LUTs
    BFC.CorrectionForLens = 0;
    BFC.CorrectionForRcvData = 0;
    BFC.connectorNeedOrder = 0;
    BFC.InterpMode = 'linear';
    BFC.DemodMode = 'IQ';
    BFC.BFMode = 'XW';
    R.BFC = BFC;

    % RF data format: 'int16', or 'half' (16 bit floating point stored as int16 bit patterns)
    R.rf_datatype = 'int16';
    if isfield(Receive, 'datatype') && ~isempty(Receive(1).datatype), R.rf_datatype = Receive(1).datatype; end

    % order of the acquisitions in the receive buffer: 'ray-major' (all pulses
    % of a ray together, so groups of rays can be transferred and
    % reconstructed while the rest is acquired) or 'pulse-major' (older data)
    R.layout = 'pulse-major';
    if isfield(P, 'rf_layout'), R.layout = P.rf_layout; end

    % beamformer: 'auto' uses the CPU if P.use_cpu_beamformer, else a compiled
    % MLBFXWave if available, else the GPU
    if strcmp(beamformer, 'auto')
        if isfield(P, 'use_cpu_beamformer') && P.use_cpu_beamformer
            beamformer = 'cpu';
        elseif exist('MLBFXWave', 'file') == 3
            beamformer = 'MLBFXWave';
        else
            beamformer = 'gpu';
        end
    end
    switch beamformer
        case 'cpu'
            R.beamform = @xw_beamform_cpu; % slow MATLAB reference, no GPU needed
            fprintf('Using the CPU beamformer (xw_beamform_cpu)\n');
        case 'MLBFXWave'
            R.beamform = @MLBFXWave;
        case 'gpu'
            fprintf('Starting the GPU (the first time on a new GPU, MATLAB compiles its GPU libraries, which can take minutes)\n');
            [gpu_ok, gpu_msg] = xw_beamform_gpu_available();
            if ~gpu_ok
                error('xw_beamform:nogpu', ['The GPU beamformer cannot run: %s.\n' ...
                    'To use the slow CPU beamformer instead, set P.use_cpu_beamformer = true or run with --cpu-beamformer.'], gpu_msg);
            end
            R.beamform = @xw_beamform_gpu;
            fprintf('Using the GPU beamformer (xw_beamform_gpu) on %s\n', gpu_msg);
        otherwise
            error('xw_beamform:beamformer', 'Unknown beamformer ''%s'': use ''auto'', ''gpu'' or ''cpu''', beamformer);
    end
    R.beamformer = beamformer;

    % groups of rays for xw_reconstruct_chunk
    R = xw_reconstruct_chunks(R, xw_get_field(P, 'num_chunks', 1));
end

function v = xw_get_field(s, name, default)
    v = default;
    if isfield(s, name) && ~isempty(s.(name)), v = s.(name); end
end
