% =========================================================================
% Cross-Amplitude Modulation (xAM) Ultrasound Imaging with a Row-Column Array
% ("sound sheet")
% =========================================================================
%
% xAM imaging (see xAM_imaging.m and Maresca et al., Phys. Rev. X 8, 041002
% (2018)) with a row-column array (RCA): the Vermon RC15gV (80 + 80 elements,
% 13.6 MHz) or RC6gV (128 + 128 elements, 6 MHz). The transmits are the same
% as for the linear array: for every ray the xWave (X: all elements of the
% aperture) and its two halves (L, R). The rays are transmitted with the
% elements of one half of the array (one orientation), received with the
% orthogonal elements of the other half, then the same with the halves
% exchanged. Every ray gives a plane (the transmit localises the ray along
% its aperture, the orthogonal receive elements resolve the other
% direction); the rays together are a volume. The two orientations are
% combined into one volume per mode.
%
% Settings: the same struct P as in xAM_imaging.m; P.probe selects the probe,
% and gives the starting values of the depth and the aperture (xw_rca_probe).
%
%   P.probe             : 'RC15gV' or 'RC6gV' (environment variable XAM_PROBE, run_xam_rca.sh --probe)
%   P.first_orientation : 1: the elements 1:N/2 transmit first, 2: the elements N/2+1:N
%   P.aperture_size_min/max : elements in the transmit aperture of a ray
%                         (per orientation)
%
% Output Data (struct BFData): volumes [depth x second axis x first axis]
% (second axis: elements that transmit second, first axis: elements that
% transmit first) of the envelope of
%   BFData.PW  : B-mode, BFData.xAM : xAM, and BFData.TimeTag.
% The axes are P.z_axis, P.axis_second and P.axis_first [m].
%
% See docs/rca.md.
% =========================================================================

clear all %#ok<CLALL>
format compact
close all

% add paths. Absolute, since VSX must be run from the Vantage root folder, not
% from this repository.
repo_root = fileparts(mfilename('fullpath'));
addpath(fullfile(repo_root, 'dependencies', 'display'))
addpath(fullfile(repo_root, 'dependencies', 'reconstruct'))
addpath(fullfile(repo_root, 'dependencies', 'sequence'))
addpath(fullfile(repo_root, 'dependencies', 'rca'))
addpath(fullfile(repo_root, 'dependencies', 'utilities'))
addpath(fullfile(repo_root, 'dependencies', 'utilities', 'save'))

% VSX must run from the root of the Verasonics software. Find it from the
% activated software on the path, so no installation path is hard-coded.
vantage_root = fileparts(which('VSX'));
assert(~isempty(vantage_root), ['Verasonics software not found: run activate in the ' ...
    'root folder of the Verasonics software first (or use run_xam_rca.sh).'])
cd(vantage_root);

%% =============================================================================
% SETUP ACQUISITION PARAMETERS
% ==============================================================================
P.probe = 'RC15gV'; % RC15gV or RC6gV
if ~isempty(getenv('XAM_PROBE')), P.probe = getenv('XAM_PROBE'); end % run_xam_rca.sh --probe
Trans.name = P.probe;
PD = xw_rca_probe(P.probe); % starting values for this probe

P.first_orientation = 1; % 1: elements 1:N/2 transmit first (Verasonics 'x elements'), 2: elements N/2+1:N

P.image_start_depth_mm = PD.image_start_depth_mm; % start depth [mm]
P.image_end_depth_mm = PD.image_end_depth_mm; % end depth [mm]

P.xwave_angles = 17; % xWave angle in degrees

P.speed_of_sound = 1480; % agar/water 1480 m/s, tissue 1540 m/s
P.image_voltage = 2.5; % set to safe number to avoid collapse

P.aperture_size_min = PD.aperture_size_min; % min number of elements in active aperture
P.aperture_size_max = PD.aperture_size_max; % max number of elements in active aperture

P.transmit_apodization = 'tukey'; % Apodization to avoid edge waves. Options: none/kaiser/hamming/tukey
P.fps = 1; % acquisition frame rate in [Hz]
if ~isempty(getenv('XAM_FPS')), P.fps = str2double(getenv('XAM_FPS')); end % tests/run_tests.sh --fps

P.save_path = fullfile(repo_root, 'data'); % default path for data saving
if ~isempty(getenv('XAM_DATA_PATH')); P.save_path = getenv('XAM_DATA_PATH'); end % e.g. set by tests/run_tests.sh
P.record_path = P.save_path; % path for recordings ('Record' button), put on a fast (NVMe) drive
P.record_num_frames = 20; % default number of frames per recording

% Voltage sweep ('Voltage sweep' button), configured with run_xam_rca.sh --sweep. Empty = no sweep.
P.sweep_voltages = xw_parse_voltages(getenv('XAM_SWEEP_VOLTAGES')); % [V], e.g. 1.6:0.4:6
P.sweep_passes = 2; % passes through the voltages (pass 2 shows whether GVs collapsed in pass 1)
P.sweep_frames = 5; % frames recorded and measured per voltage
P.sweep_save_mode = 'images'; % saved per voltage: 'images' or 'rf'
if ~isempty(getenv('XAM_SWEEP_SAVE')); P.sweep_save_mode = getenv('XAM_SWEEP_SAVE'); end
if ~isempty(getenv('XAM_SWEEP_FRAMES')); P.sweep_frames = str2double(getenv('XAM_SWEEP_FRAMES')); end
P.sweep_settle_frames = 2; % frames discarded after each voltage change
P.sweep_settle_s = 1; % minimum settle time after a voltage increase [s]
P.sweep_settle_s_down = 3; % minimum settle time after a voltage decrease [s]
P.sweep_max_voltage = 25; % sweep refuses voltages above this [V]

P.tpc_settle_us = 8000; % time reserved for a change of the voltage [us] (0.8 to 8 ms, depending on the voltage step)

% Burst ('Burst' button): frames at the imaging voltage, frames at the burst voltage, frames at the imaging voltage.
% The burst voltage is TPC profile 2 (VSX slider 'High Voltage P2'), the imaging voltage profile 1 ('High Voltage P1').
% The burst uses focused transmits (not xWaves) and its own, higher frame rate, as in xAM_imaging.m, for both
% orientations; the RF of the frames is kept in memory and reconstructed after the burst, see docs/rca.md.
P.burst_voltage = PD.burst_voltage; % [V] (the limit of the probe is Trans.maxHighVoltage)
P.burst_pre_frames = 10;
P.burst_collapse_frames = 46;
P.burst_post_frames = 0;
P.burst_start_depth_mm = PD.burst_start_depth_mm; % image depth of the burst [mm]
P.burst_end_depth_mm = PD.burst_end_depth_mm;
P.burst_num_tx = PD.burst_num_tx; % elements in the transmit aperture. The rays are all positions of the aperture
P.burst_focus_mm = PD.burst_focus_mm; % transmit focus [mm]
P.burst_tw_half_cycles = 7; % length of the transmit pulse in half cycles
P.burst_frame_delay_factor = 10; % time between frames, in times the time between acquisitions
P.burst_confirm = true; % ask for confirmation before a burst: it collapses gas vesicles irreversibly
% tests/run_tests.sh uses a short burst at a safe voltage and no confirmation
if ~isempty(getenv('XAM_BURST_VOLTAGE')), P.burst_voltage = str2double(getenv('XAM_BURST_VOLTAGE')); end
if ~isempty(getenv('XAM_BURST_FRAMES')), burst_frames = str2double(strsplit(getenv('XAM_BURST_FRAMES'), ',')); [P.burst_pre_frames, P.burst_collapse_frames, P.burst_post_frames] = deal(burst_frames(1), burst_frames(2), burst_frames(3)); end
if strcmp(getenv('XAM_BURST_CONFIRM'), '0'), P.burst_confirm = false; end

%% =============================================================================
% INPUT VALIDATION
% ==============================================================================
assert(P.image_end_depth_mm >= P.image_start_depth_mm, 'Image end depth must be larger than start depth')
assert(P.aperture_size_min < P.aperture_size_max, 'Min aperture size must be smaller than max aperture size')
assert(ismember(P.first_orientation, [1 2]), 'P.first_orientation must be 1 or 2')
assert(all(P.sweep_voltages <= P.sweep_max_voltage), 'Sweep voltages must not exceed P.sweep_max_voltage = %g V', P.sweep_max_voltage)
assert(all(P.sweep_voltages >= 1.6), 'Sweep voltages must be at least 1.6 V (Vantage minimum)')
assert(ismember(P.sweep_save_mode, {'images', 'rf'}), 'P.sweep_save_mode must be ''images'' or ''rf''')
assert(isfinite(P.sweep_frames) && P.sweep_frames >= 1 && P.sweep_frames == round(P.sweep_frames), 'Sweep frames per voltage must be a positive integer')
BP = xw_burst_plan(P.burst_pre_frames, P.burst_collapse_frames, P.burst_post_frames); % frames of a burst
assert(P.burst_voltage >= 1.6, 'Burst voltage must be at least 1.6 V (Vantage minimum)')
assert(P.burst_end_depth_mm > P.burst_start_depth_mm, 'Burst end depth must be larger than start depth')

%% =============================================================================
% TRANSDUCER PARAMETERS
% ==============================================================================
Trans.units = 'mm';
Trans = computeTrans(Trans);
assert(Trans.type == 4, '%s is not a row-column array (Trans.type = %i)', Trans.name, Trans.type)
assert(P.burst_voltage <= Trans.maxHighVoltage, 'Burst voltage %g V is above the limit of %s of %g V', P.burst_voltage, Trans.name, Trans.maxHighVoltage)
assert(P.image_voltage <= Trans.maxHighVoltage, 'Image voltage %g V is above the limit of %s of %g V', P.image_voltage, Trans.name, Trans.maxHighVoltage)
assert(all(P.sweep_voltages <= Trans.maxHighVoltage), 'Sweep voltages are above the limit of %s of %g V', Trans.name, Trans.maxHighVoltage)
G = xw_rca_geometry(Trans, P.first_orientation); % halves of the array: transmit and receive elements of both orientations
assert(P.aperture_size_max < G.num_half, 'Max aperture size must be smaller than the number of elements per half (%i)', G.num_half)
assert(P.burst_num_tx < G.num_half, 'Burst aperture (P.burst_num_tx) must be smaller than the number of elements per half (%i)', G.num_half)

%% =============================================================================
% SYSTEM PARAMETERS
% ==============================================================================
% 256 channels also for the RC15gV (160 elements), as in the Verasonics RC examples
Resource.Parameters.numTransmit = 256; % number of transmit channels
Resource.Parameters.numRcvChannels = 256; % number of receive channels
Resource.Parameters.speedOfSound = P.speed_of_sound; % speed of sound [m/s]
Resource.Parameters.verbose = 1; % controls output warnings
Resource.Parameters.speedCorrectionFactor = 1.0;
Resource.Parameters.simulateMode = double(strcmp(getenv('XAM_SIMULATE'), '1')); % 1: simulation, 0: hardware (run_xam_rca.sh --sim sets 1)
Resource.Parameters.fakeScanhead = 0;
Resource.VDAS.dmaTimeout = 1000 * 4; % 4 seconds
Resource.VDAS.acqTimeTagEnable = 1;
Resource.Parameters.waitForProcessing = 1;

% Advanced options
P.num_accumulations = 1; % no accumulation in the RCA sequence
P.use_adaptive_xwave_angle = true; % if true updates the xWave Angles dependent on the imaging depth
P.use_half_pitch_scanning = false; % rays between the elements as well: twice the rays and the data
P.transmit_frequency = Trans.frequency; % transducer transmit frequency [MHz]
P.use_cpu_beamformer = strcmp(getenv('XAM_CPU_BEAMFORMER'), '1'); % slow MATLAB beamformer instead of the GPU one

P.num_pulses = 3; % number of pulses in xAM pulse sequence, hardcoded
P.rf_datatype = 'int16'; % RF data format: 'int16', or 'half' (16 bit floating point)
if ~isempty(getenv('XAM_RF_DATATYPE')), P.rf_datatype = getenv('XAM_RF_DATATYPE'); end % run_xam_rca.sh --float16
assert(ismember(P.rf_datatype, {'int16', 'half'}), 'P.rf_datatype must be ''int16'' or ''half''');
P.num_chunks = 8; % the frame is transferred and reconstructed in this many groups of rays, while the next rays are acquired. A chunk has the rays of one orientation, so at least 2.
P.timetag_enabled = 1; % debug option, see time tags of frames
P.num_rf_frames = 4; % must be >4 or even number, don't change
P.beamform_image_modes = {'PW', 'xAM'}; % PW = bf(\)+bf(/), xBmode = bf(X), xAM = bf(X-\-/)

% choose rays for pitch or pitch/2 scanning, along the axis of the transmit elements (per orientation)
step = 1 / (P.use_half_pitch_scanning + 1);
P.ray_positions = ceil(P.aperture_size_min / 2) + 1:step:G.num_half - floor(P.aperture_size_min / 2);
P.num_rays = numel(P.ray_positions); % per orientation
P.num_orientations = 2;
P.num_rays_total = P.num_orientations * P.num_rays;

% warn user about max angle used
if P.use_adaptive_xwave_angle
    P.max_image_depth = (P.aperture_size_max * Trans.spacingMm * 1e-3) / 2 * cotd(max(P.xwave_angles));
    if P.max_image_depth < P.image_end_depth_mm * 1e-3
        warning('Imaging depth too high for combination of angles. Max depth of intersecting xWave is %.2fmm. Either\n - Decrease imaging depth\n - Set P.use_adaptive_xwave_angle to false\n - Dont trust xAM results below %.2fmm\n - Decrease the max angle', P.max_image_depth * 1e3, P.max_image_depth * 1e3)
    end
end
assert(P.num_rf_frames >= 4, 'num_rf_frames must be at least 4');

% some additional dependent parameters
P.scale_wvl2mm = (Resource.Parameters.speedOfSound / Trans.frequency) * 1e-3; % length of 1 wavelength in mm
P.scale_mm2wvl = Trans.frequency / (Resource.Parameters.speedOfSound / 1000); %wavelength per mm
P.num_angles = numel(P.xwave_angles);

% receive buffer: all pulses of a ray together (so that groups of rays, chunks, can be transferred
% and reconstructed while the next rays are acquired); the rays of orientation 1, then those of orientation 2
P.rf_layout = 'ray-major';
P.chunks = xw_rca_chunk_plan(P.num_rays, P.num_chunks);
P.num_chunks = numel(P.chunks);

% hooks of the shared code (record, sweep, display) for volumes
P.plot_function = 'xw_rca_plot';
P.crossing_roi_function = 'xw_rca_crossing_roi';
P.image_bytes_per_frame = numel(P.image_start_depth_mm:P.scale_wvl2mm / 2:P.image_end_depth_mm) * P.num_rays ^ 2 ...
    * 4 * numel(P.beamform_image_modes) * 2; % real single volumes, raw + persisted

% specify Media object: point targets in wavelengths (the simulation, run_xam_rca.sh --sim)
depth_wvl = P.image_end_depth_mm * P.scale_mm2wvl;
lateral_wvl = 0.25 * G.num_half * Trans.spacingMm * P.scale_mm2wvl;
Media.MP = [0, 0, 0.3 * depth_wvl, 1; lateral_wvl, lateral_wvl, 0.3 * depth_wvl, 1; -lateral_wvl, lateral_wvl, 0.3 * depth_wvl, 1; ...
    lateral_wvl, -lateral_wvl, 0.6 * depth_wvl, 1; -lateral_wvl, -lateral_wvl, 0.6 * depth_wvl, 1; 0, 0, 0.6 * depth_wvl, 1];
Media.numPoints = size(Media.MP, 1);
Media.attenuation = -0.5;
Media.function = 'movePoints';

%% =============================================================================
% RESOURE BUFFERS
% ==============================================================================

% determine demod frequency, and compute Nz_RF
TxFreq = 250 ./ (2 .* ((6:197).'));
demodFreqsValid = TxFreq(rem(250, TxFreq * 4) == 0);
[~, idx] = min(abs(Trans.frequency - demodFreqsValid));
demodFrequency = demodFreqsValid(idx);
P.demod_ratio = demodFrequency / Trans.frequency; % for the number of samples of the burst acquisitions

% longest path: to the farthest receive element
maxAcqLength = ceil(sqrt(P.image_end_depth_mm ^ 2 + ((G.num_half - 1) * Trans.spacingMm) ^ 2)); % [mm]
maxAcqLengthWvl = maxAcqLength * P.scale_mm2wvl;
P.Nz_RF = (ceil(maxAcqLengthWvl * 2 * 4 * demodFrequency / Trans.frequency / 128) * 128); %2*4*enddepth*factor (beam forming factor)

% allocate resources
Resource.RcvBuffer(1).datatype = 'int16';
Resource.RcvBuffer(1).rowsPerFrame = P.num_rays_total * P.num_angles * P.num_pulses * P.Nz_RF;
Resource.RcvBuffer(1).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(1).numFrames = P.num_rf_frames;

%% Timing parameters
P.num_tx_per_frame = P.num_angles * P.num_pulses * P.num_rays_total;
P.ttna = round(maxAcqLength * 5 * 1e-3 / Resource.Parameters.speedOfSound * 1e6); % in microseconds!
P.time_per_frame = P.ttna * P.num_tx_per_frame;
P.max_framerate = 1e6 / P.time_per_frame;

%% =============================================================================
% TRANSMIT WAVEFORM
% ==============================================================================
% Specify Transmit Waveform (TW) structure array
TW(1).type = 'parametric';
TW(1).Parameters = [P.transmit_frequency, 0.67, 1, 1];

%% =============================================================================
% TRANSMIT AND RECEIVE STRUCTURES
% ==============================================================================

% The transmit delays and apodizations are made for the transmit half of the array as a linear array
% (xw_setup_build_transmit, as for the linear array, with the geometry G.tx_view). They are the same for
% both orientations, which use the elements of their half.
n_tx_o = P.num_pulses * P.num_angles * P.num_rays; % transmits of one orientation
tx_template = struct('waveform', 1, 'Origin', [0.0, 0.0, 0.0], 'Steer', [0.0, 0.0], ...
    'Apod', zeros(1, G.num_half), 'focus', 0, 'Delay', zeros(1, G.num_half));
TX_half = repmat(tx_template, 1, n_tx_o);
P.ray_angle = zeros(P.num_angles, P.num_rays); % xWave angles per ray
for idx_ray = 1:P.num_rays
    for idx_angle = 1:P.num_angles
        idx_tx = idx_angle + (idx_ray - 1) * P.num_angles;
        TX_half = xw_setup_build_transmit(TX_half, idx_tx, idx_ray, idx_angle, G.tx_view{1}, P); % also sets P.ray_half_aperture etc. in the base workspace
    end
end

% TX of the whole array: orientation 1, then orientation 2. Order within an orientation: pulse (X, L, R), ray, angle
tx_template.Apod = zeros(1, Trans.numelements);
tx_template.Delay = zeros(1, Trans.numelements);
TX = repmat(tx_template, 1, P.num_orientations * n_tx_o);
tx_index = @(orientation, ray, pulse, angle) (orientation - 1) * n_tx_o + angle + (ray - 1) * P.num_angles + pulse * P.num_rays * P.num_angles;
for o = 1:P.num_orientations
    for idx_ray = 1:P.num_rays
        for idx_angle = 1:P.num_angles
            for idx_pulse = 0:P.num_pulses - 1
                half_index = idx_angle + (idx_ray - 1) * P.num_angles + idx_pulse * P.num_rays * P.num_angles;
                k = tx_index(o, idx_ray, idx_pulse, idx_angle);
                TX(k).waveform = 1;
                TX(k).Apod(G.tx_elements{o}) = TX_half(half_index).Apod;
                TX(k).Delay(G.tx_elements{o}) = TX_half(half_index).Delay;
            end
        end
    end
end

TPC(1).hv = P.image_voltage; % imaging voltage
TPC(2).hv = P.burst_voltage; % burst voltage, used by the burst events

% dummy transmit without active elements, to change the TPC profile between frames
TX(end + 1) = tx_template;
P.dummy_tx = numel(TX);

% Specify Receive structure arrays. The receive elements of an orientation are the other half of the array.
nRcvObj_p_frame = P.num_pulses * P.num_rays_total * P.num_angles;
Receive = repmat(struct('Apod', zeros(1, Trans.numelements), ...
    'startDepth', 0, ...
    'endDepth', maxAcqLengthWvl, ...
    'TGC', 1, ...
    'bufnum', 1, ...
    'framenum', 1, ...
    'acqNum', 1, ...
    'sampleMode', 'NS200BW', ...
    'datatype', P.rf_datatype, ...
    'mode', 0, ... % newly acquired data is written to the storage memory, replacing any previous data
    'callMediaFunc', 0), ...
    1, nRcvObj_p_frame * P.num_rf_frames);

% Receive structures are ordered by acquisition number within a frame: for every ray of the frame
% (orientation 1 first) the 3 pulses (X, L, R) with all angles each. g is the number of the ray in the frame.
ray_g = @(orientation, ray) ray + (orientation - 1) * P.num_rays;
rcv_acq_num = @(g, pulse, angle) ((g - 1) * P.num_pulses + pulse) * P.num_angles + angle;
rcv_index = @(g, pulse, angle, frame) rcv_acq_num(g, pulse, angle) + (frame - 1) * nRcvObj_p_frame;

for o = 1:P.num_orientations
    for idx_ray = 1:P.num_rays
        for idx_angle = 1:P.num_angles
            for idx_frame = 1:P.num_rf_frames
                for idx_pulse = 0:P.num_pulses - 1 % X pulse, left active aperture, right active aperture
                    g = ray_g(o, idx_ray);
                    idx = rcv_index(g, idx_pulse, idx_angle, idx_frame);
                    if (g == 1 && idx_angle == 1 && idx_pulse == 0)
                        Receive(idx).callMediaFunc = 1;
                    end
                    Receive(idx).Apod(G.rx_elements{o}) = 1.0; % the orthogonal elements
                    Receive(idx).mode = 0;
                    Receive(idx).framenum = idx_frame;
                    Receive(idx).acqNum = rcv_acq_num(g, idx_pulse, idx_angle);
                end
            end
        end
    end
end

%% =============================================================================
% TIME GAIN CONTROL
% ==============================================================================
TGC(1).CntrlPts = 800 * ones(1, 8); % 1023 is max gain
TGC(1).rangeMax = P.image_end_depth_mm * P.scale_mm2wvl; % in wavelengths
TGC(1).Waveform = computeTGCWaveform(TGC(1));

%% =============================================================================
% BURST: FOCUSED TRANSMITS AND RECEIVE BUFFER
% ==============================================================================
% The burst is acquired in its own receive buffer that holds all frames of the burst, see xw_rca_setup_burst.
% Transmit waveform 2, TGC 2, receive buffer 2. The frames are reconstructed after the burst.
SB = xw_rca_setup_burst(P, Trans, G, BP.num_frames, numel(TX), numel(Receive));
TX = [TX, SB.TX];
Receive = [Receive, SB.Receive];
TW(2) = SB.TW;
TGC(2) = SB.TGC;
Resource.RcvBuffer(2).datatype = 'int16';
Resource.RcvBuffer(2).rowsPerFrame = SB.rows_per_frame;
Resource.RcvBuffer(2).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(2).numFrames = BP.num_frames + mod(BP.num_frames, 2); % VSX needs 1 or an even number of frames
P.burst_num_rays_o = SB.num_rays; % rays per orientation
P.burst_ray_centers = SB.ray_centers; % [mm] along the axis of the transmit elements, per orientation
P.burst_delay_centre = SB.delay_centre;
P.burst_first_receive = SB.first_receive;
P.burst_x_axis = SB.ray_centers{1}; % [mm]
P.burst_z_axis = [P.burst_start_depth_mm, P.burst_end_depth_mm];
P.burst_ttna = 3 * SB.max_acq_length_mm / P.speed_of_sound * 2 * 1e3; % time between acquisitions [us]
P.burst_ttna_frame = P.burst_frame_delay_factor * P.burst_ttna; % time after the last acquisition of a frame [us]
P.burst_frame_period = (P.burst_ttna * 3 * P.num_orientations * SB.num_rays + P.burst_ttna_frame) * 1e-6; % nominal time between frames [s]
P.burst_finish_function = 'xw_rca_burst_finish'; % hook of xw_sequence_start

%% =============================================================================
% PROCESS FUNCTIONS
% ==============================================================================

% one process per group of rays, reconstructing when these have been transferred
np = 1;
PN.image_reconstruct_chunk = zeros(1, P.num_chunks);
EF = struct('FunctionName', {}, 'FunctionHandle', {});
for idx_chunk = 1:P.num_chunks
    PN.image_reconstruct_chunk(idx_chunk) = np;
    Process(np).classname = 'External';
    Process(np).method = sprintf('xw_rca_chunk%02i', idx_chunk);
    Process(np).Parameters = {'srcbuffer', 'receive', ...
        'srcbufnum', 1, ...
        'srcframenum', -1, ...
        'dstbuffer', 'none'};
    EF(idx_chunk) = struct('FunctionName', Process(np).method, ...
        'FunctionHandle', @(RData) xw_rca_beamform_run(RData, idx_chunk));
    np = np + 1;
end

PN.image_reconstruct_init = np;
Process(np).classname = 'External';
Process(np).method = 'xw_rca_beamform_run';
Process(np).Parameters = {'srcbuffer', 'receive', ...
    'srcbufnum', 1, ...
    'srcframenum', 1, ...
    'dstbuffer', 'none'};
np = np + 1;

PN.image_display = np;
Process(np).classname = 'External';
Process(np).method = 'xw_rca_plot';
Process(np).Parameters = {'srcbuffer', 'none', ...
    'dstbuffer', 'none'};
np = np + 1;

% burst: copy the RF of every frame while it runs, reconstruct and keep the volume of each frame at the end of the burst
PN.burst_capture = np;
Process(np).classname = 'External';
Process(np).method = 'xw_rca_burst_capture';
Process(np).Parameters = {'srcbuffer', 'receive', ...
    'srcbufnum', 2, ...
    'srcframenum', -1, ...
    'dstbuffer', 'none'};
np = np + 1;

PN.burst_save = zeros(1, BP.num_frames);
for idx_frame = 1:BP.num_frames
    PN.burst_save(idx_frame) = np;
    Process(np).classname = 'External';
    Process(np).method = 'xw_rca_burst_save_image';
    Process(np).Parameters = {'srcbuffer', 'none', ...
        'dstbuffer', 'none'};
    np = np + 1;
end

PN.burst_finish = np;
Process(np).classname = 'External';
Process(np).method = 'xw_rca_burst_finish';
Process(np).Parameters = {'srcbuffer', 'none', ...
    'dstbuffer', 'none'};
np = np + 1;

PN.saveAcqPars = np;
Process(np).classname = 'External';
Process(np).method = 'xw_sequence_save_acquisition_parameters';
Process(np).Parameters = {'srcbuffer', 'none', ...
    'dstbuffer', 'none'};
np = np + 1;

%% =============================================================================
% SEQUENCE CONTROL
% ==============================================================================

SeqControl(1).command = 'timeToNextAcq';
SeqControl(1).argument = P.ttna;
SC.ttna = 1;
SeqControl(2).command = 'returnToMatlab';
SC.matlab = 2;
SeqControl(3).command = 'jump';
SeqControl(3).argument = []; % set later
SC.jump = 3;
SeqControl(4).command = 'stop'; % time between frames
SC.stop = 4;
SeqControl(5).command = 'timeToNextAcq';
P.ttna_frame = 1e6 / P.fps - P.ttna * (P.num_tx_per_frame);
assert(P.ttna_frame > P.ttna, 'frame rate too high! Max is %.2f Hz', P.max_framerate)
SeqControl(5).argument = P.ttna_frame; %  4e6; % 4 seconds max! in microseconds!
SC.ttna_frame = 5;
SeqControl(6).command = 'timeToNextAcq';
SeqControl(6).argument = P.tpc_settle_us; % after a change of the voltage
SC.tpc_settle = 6;
SeqControl(7).command = 'setTPCProfile';
SeqControl(7).argument = 1; % imaging voltage
SeqControl(7).condition = 'next';
SC.tpc_imaging = 7;
SeqControl(8).command = 'timeToNextAcq';
SeqControl(8).argument = P.burst_ttna; % between the acquisitions of a burst
SC.ttna_burst = 8;
SeqControl(9).command = 'timeToNextAcq';
SeqControl(9).argument = P.burst_ttna_frame; % between the frames of a burst
SC.ttna_burst_frame = 9;
SeqControl(10).command = 'setTPCProfile';
SeqControl(10).argument = 2; % burst voltage
SeqControl(10).condition = 'next';
SC.tpc_burst = 10;
SeqControl(11).command = 'jump';
SeqControl(11).argument = []; % set later, to EN.StartEvent
SC.jump_start = 11;
tpc_sc = [SC.tpc_imaging, SC.tpc_burst]; % setTPCProfile of TPC profile 1, 2

nsc = length(SeqControl) + 1;

%% =============================================================================
% EVENT STRUCTURES
% ==============================================================================

n = 1;

Event(n).info = 'initialize beamformer';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = PN.image_reconstruct_init;
Event(n).seqControl = SC.matlab;
n = n + 1;

Event(n).info = 'initialize display';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = PN.image_display;
Event(n).seqControl = SC.matlab;
n = n + 1;

% save acquisition paramters
Event(n).info = 'saveAcqPars';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = PN.saveAcqPars;
Event(n).seqControl = SC.matlab;
n = n + 1;

Event(n).info = 'enter freeze and stop hardware';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = 0;
Event(n).seqControl = [SC.matlab, SC.stop];
n = n + 1;

% when the sequence is started: imaging voltage (TPC profile 1)
EN.StartEvent = n;
Event(n).info = 'Set imaging voltage';
Event(n).tx = P.dummy_tx;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = 0;
Event(n).seqControl = [SC.tpc_settle, SC.tpc_imaging];
n = n + 1;

EN.Loop = n;
SeqControl(SC.jump).argument = EN.Loop; % set here

pulse_names = {'X', 'L', 'R'};
for idx_frame = 1:P.num_rf_frames
    for idx_chunk = 1:P.num_chunks
        c = P.chunks(idx_chunk);
        for idx_ray = c.rays
            g = ray_g(c.orientation, idx_ray);
            for idx_angle = 1:P.num_angles
                for idx_pulse = 0:P.num_pulses - 1
                    Event(n).info = sprintf('Acquire %s O%i R%03i A%02i F%02i', pulse_names{idx_pulse + 1}, c.orientation, idx_ray, idx_angle, idx_frame);
                    Event(n).tx = tx_index(c.orientation, idx_ray, idx_pulse, idx_angle);
                    Event(n).rcv = rcv_index(g, idx_pulse, idx_angle, idx_frame);
                    Event(n).recon = 0;
                    Event(n).process = 0;
                    Event(n).seqControl = SC.ttna; % Time between acquisitions
                    n = n + 1;
                end
            end
        end

        if idx_chunk == P.num_chunks
            Event(n - 1).seqControl = SC.ttna_frame; % Time between frames
        end

        % transfer the rays acquired so far, reconstruct them while the next rays are acquired
        Event(n).info = sprintf('Transfer chunk %i to host buffer', idx_chunk);
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc;
        SeqControl(nsc).command = 'transferToHost';
        nsc = nsc + 1;
        n = n + 1;

        Event(n).info = sprintf('waitForTransferComplete chunk %i', idx_chunk);
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc;
        SeqControl(nsc).command = 'waitForTransferComplete';
        SeqControl(nsc).argument = nsc - 1;
        nsc = nsc + 1;
        n = n + 1;

        Event(n).info = sprintf('Image Reconstruct chunk %i', idx_chunk);
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = PN.image_reconstruct_chunk(idx_chunk);
        Event(n).seqControl = 0;
        n = n + 1;

        Event(n).info = sprintf('markTransferProcessed chunk %i', idx_chunk);
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc;
        SeqControl(nsc).command = 'markTransferProcessed';
        SeqControl(nsc).argument = nsc - 2;
        nsc = nsc + 1;
        n = n + 1;
    end

    Event(n).info = 'Image Display';
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = PN.image_display;
    Event(n).seqControl = SC.matlab;
    n = n + 1;
end

Event(n).info = 'Jump back to AcquisitionLoop.';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = 0;
Event(n).seqControl = [SC.matlab, SC.jump]; % jump back to the start of the loop
n = n + 1;

% ------------------------------------------------------------------------------
% Burst, started by the Burst button (xw_burst_start restarts the sequence at EN.Burst).
%
% All frames are acquired with focused transmits, one after the other at a high frame rate, each
% transferred to the receive buffer 2 that holds all frames. With Resource.Parameters.waitForProcessing = 1
% the hardware waits, before each transfer, until the software has asked for the latest frame: after every
% frame xw_rca_burst_capture copies the RF of the frame to host memory (no reconstruction, which would
% slow the burst down). The volumes are reconstructed and kept all at the end of the burst, after the last
% acquisition (xw_rca_burst_save_image), and saved by xw_rca_burst_finish.
% ------------------------------------------------------------------------------
tth_sc = nsc + (0:BP.num_frames - 1); % SeqControl of the transfer of each frame
nsc = nsc + BP.num_frames;

% clear the 'transferred, not processed' flags of the transfers (left set by a previous burst)
EN.Burst = n;
for idx_frame = 1:BP.num_frames
    Event(n).info = sprintf('Burst: clear transfer flag of frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = 0;
    Event(n).seqControl = nsc;
    SeqControl(nsc).command = 'markTransferProcessed';
    SeqControl(nsc).argument = tth_sc(idx_frame);
    nsc = nsc + 1;
    n = n + 1;
end

for idx_frame = 1:BP.num_frames
    if BP.switch_before(idx_frame) > 0 % imaging voltage, burst voltage
        Event(n).info = sprintf('Burst: set TPC profile %i', BP.switch_before(idx_frame));
        Event(n).tx = P.dummy_tx;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = [SC.tpc_settle, tpc_sc(BP.switch_before(idx_frame))];
        n = n + 1;
    end

    for o = 1:P.num_orientations
        for idx_ray = 1:SB.num_rays
            for idx_pulse = 1:3 % full aperture, odd elements off, even elements off
                Event(n).info = sprintf('Burst: acquire O%i R%03i P%i F%03i', o, idx_ray, idx_pulse, idx_frame);
                Event(n).tx = SB.tx_index(o, idx_pulse, idx_ray);
                Event(n).rcv = SB.rcv_index(o, idx_pulse, idx_ray, idx_frame);
                Event(n).recon = 0;
                Event(n).process = 0;
                Event(n).seqControl = SC.ttna_burst;
                n = n + 1;
            end
        end
    end
    Event(n - 1).seqControl = [SC.ttna_burst_frame, tth_sc(idx_frame)];
    SeqControl(tth_sc(idx_frame)).command = 'transferToHost'; % transfer the frame to the host buffer

    Event(n).info = sprintf('Burst: waitForTransferComplete frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = 0;
    Event(n).seqControl = nsc;
    SeqControl(nsc).command = 'waitForTransferComplete';
    SeqControl(nsc).argument = tth_sc(idx_frame);
    nsc = nsc + 1;
    n = n + 1;

    Event(n).info = sprintf('Burst: copy the RF of frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = PN.burst_capture;
    Event(n).seqControl = 0;
    n = n + 1;

    Event(n).info = sprintf('Burst: markTransferProcessed frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = 0;
    Event(n).seqControl = nsc;
    SeqControl(nsc).command = 'markTransferProcessed';
    SeqControl(nsc).argument = tth_sc(idx_frame);
    nsc = nsc + 1;
    n = n + 1;
end

% reconstruct and keep all frames, one after the other
for idx_frame = 1:BP.num_frames
    Event(n).info = sprintf('Burst: reconstruct frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = PN.burst_save(idx_frame);
    Event(n).seqControl = 0;
    n = n + 1;
end

% end of the burst: save the data, and return to the acquisition loop (restarts at EN.StartEvent)
Event(n).info = 'Burst: finish';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = PN.burst_finish;
Event(n).seqControl = 0;
n = n + 1;

% the events must not end here: the sequence would continue with event 1, which freezes it
SeqControl(SC.jump_start).argument = EN.StartEvent;
Event(n).info = 'Burst: return to Matlab, back to the acquisition loop';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = 0;
Event(n).seqControl = [SC.matlab, SC.jump_start];
n = n + 1;

%% =============================================================================
% User specified UI Control Elements
% =============================================================================
if P.timetag_enabled == 1
    UI(1).Statement = 'xw_setup_timetag()';
end

n_ui = 1;
% button to restart sequence
UI(n_ui).Control = {'UserB1', 'Style', 'VsPushButton', 'Label', 'Start Seq.'};
UI(n_ui).Callback = {'xw_sequence_start(hObject)'};
n_ui = n_ui + 1;

UISTATES = struct;

% Change persistence
P.image_persistence = 1;
UISTATES.persistence = P.image_persistence;
UI(n_ui).Control = {'UserB6', 'Style', 'VsSlider', 'Label', 'Persistence', ...
    'SliderMinMaxVal', [0.1, 1, P.image_persistence], ...
    'SliderStep', [0.01, 0.1], 'ValueFormat', '%1.2f'};
UI(n_ui).Callback = {'xw_change_persistence(UIValue)'};
n_ui = n_ui + 1;

UISTATES.dr_bmode = 40; % dynamic range B-mode
% UserC7 and UserC8 hold the VSX PreSet and Tools controls, so use C6 and C5
UI(n_ui).Control = {'UserC6', 'Style', 'VsSlider', 'Label', 'DR B-Mode', ...
    'SliderMinMaxVal', [0, 60, UISTATES.dr_bmode], ...
    'SliderStep', [0.01, 0.1], 'ValueFormat', '%2.1fdB'};
UI(n_ui).Callback = {'xw_change_dr(''bmode'', UIValue)'};
n_ui = n_ui + 1;

UISTATES.dr_xam = 20; % dynamic range minimum
UI(n_ui).Control = {'UserC5', 'Style', 'VsSlider', 'Label', 'DR xAM', ...
    'SliderMinMaxVal', [0, 30, UISTATES.dr_xam], ...
    'SliderStep', [0.01, 0.1], 'ValueFormat', '%2.1fdB'};
UI(n_ui).Callback = {'xw_change_dr(''xam'', UIValue)'};
n_ui = n_ui + 1;

% save mode for both 'Save Data' and 'Record': beamformed images or raw RF
% the button group always starts on its first button, so list the initial mode first
UISTATES.save_mode = 'images';
if strcmp(getenv('XAM_SAVE_MODE'), 'rf'); UISTATES.save_mode = 'rf'; end
UISTATES.save_mode_order = {'images', 'rf'};
save_mode_labels = {'xAM images', 'Raw RF'};
if strcmp(UISTATES.save_mode, 'rf')
    UISTATES.save_mode_order = fliplr(UISTATES.save_mode_order);
    save_mode_labels = fliplr(save_mode_labels);
end
UI(n_ui).Control = {'UserB4', 'Style', 'VsButtonGroup', 'Title', 'Save mode', ...
    'NumButtons', 2, 'Labels', save_mode_labels};
UI(n_ui).Callback = {'xw_change_save_mode(UIState)'};
n_ui = n_ui + 1;

% save a snapshot of the frozen sequence
UI(n_ui).Control = {'UserC1', 'Style', 'VsPushButton', 'Label', 'Save Data'};
UI(n_ui).Callback = {'xw_save_data()'};
n_ui = n_ui + 1;

% record a series of frames while running (press again to stop early)
UISTATES.record_num_frames = P.record_num_frames;
UI(n_ui).Control = {'UserC3', 'Style', 'VsSlider', 'Label', 'Rec. frames', ...
    'SliderMinMaxVal', [1, 500, UISTATES.record_num_frames], ...
    'SliderStep', [1 / 499, 10 / 499], 'ValueFormat', '%3.0f'};
UI(n_ui).Callback = {'xw_change_record_frames(UIValue)'};
n_ui = n_ui + 1;

UI(n_ui).Control = {'UserC2', 'Style', 'VsPushButton', 'Label', 'Record'};
UI(n_ui).Callback = {'xw_record_start()'};
n_ui = n_ui + 1;
XWRecord = struct('active', false); % recording state, see xw_record_start

% one burst: frames at the burst voltage (collapse), saved to P.record_path. Disabled while saving, see xw_burst_update_button
UI(n_ui).Control = {'UserC4', 'Style', 'VsPushButton', 'Label', 'Burst'};
UI(n_ui).Callback = {'xw_burst_start()'};
n_ui = n_ui + 1;
XWBurst = struct('active', false); % burst state, see xw_burst_start

% voltage sweep, only when configured (run_xam_rca.sh --sweep); press again to stop
if ~isempty(P.sweep_voltages)
    UI(n_ui).Control = {'UserB2', 'Style', 'VsPushButton', 'Label', 'Voltage sweep'};
    UI(n_ui).Callback = {'xw_sweep_start()'};
    n_ui = n_ui + 1;
end
XWSweep = struct('active', false); % sweep state, see xw_sweep_start

% configure saveDataMenu
P.matfile_file_name = 'xAM_imaging_RCA.mat';
SaveDataMenuSettings = saveDataMenu('defaults'); % call with 1 output arg and one input arg to obtain defaults
SaveDataMenuSettings.filename = P.matfile_file_name;
SaveDataMenuSettings.custom_figures = {2};
SaveDataMenuSettings.folder = P.save_path;
SaveDataMenuSettings.custom_variables = {'UISTATES', 'BFData', 'BFData_raw'};
BFData_raw = []; BFData = [];

% save sequence definition for VSX
matfile_dir = fullfile(repo_root, 'MatFiles');
if ~isfolder(matfile_dir); mkdir(matfile_dir); end
filename = fullfile(matfile_dir, P.matfile_file_name); % picked up by VSX
save(filename);

% Automatically Launch Verasonics
VSX
