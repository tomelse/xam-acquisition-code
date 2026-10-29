% =========================================================================
% Cross-Amplitude Modulation (xAM) Ultrasound Imaging
% =========================================================================
%
% This script implements the xAM imaging paradigm for artifact-free detection
% of gas vesicles (GVs). By transmitting cross-propagating plane waves,
% xAM suppresses nonlinear propagation artifacts while preserving nonlinear
% contrast from GVs, as described in:
%
%   Maresca et al., "Nonlinear Ultrasound Imaging of Nanoscale Acoustic Biomolecules"
%   Phys. Rev. X 8, 041002 (2018). DOI: 10.1103/PhysRevX.8.041002
%
% Authors:
%   Rick Waasdorp (r.waasdorp@tudelft.nl)
%   David Maresca (d.maresca@tudelft.nl)
%
% -------------------------------------------------------------------------
% Parameter Reference (struct P)
% -------------------------------------------------------------------------
%
% Basic parameters:
%   P.image_start_depth_mm   : Start depth of imaging region [mm]
%   P.image_end_depth_mm     : End depth of imaging region [mm]
%   P.xwave_angles           : xWave angle [degrees]
%   P.speed_of_sound         : Speed of sound in medium
%                               (1480 m/s in water/agar, 1540 m/s in tissue)
%   P.image_voltage          : Transmit voltage [V]. Set safely to avoid GV collapse
%   P.aperture_size_min      : Minimum number of elements in active aperture
%                               (e.g. 48 for wide FOV)
%   P.aperture_size_max      : Maximum number of elements in active aperture
%   P.transmit_apodization   : Apodization function to reduce edge waves.
%                               Options: 'none', 'kaiser', 'hamming', 'tukey'
%   P.fps                    : Acquisition frame rate [Hz]
%   P.save_path              : Default path for saving data
%   P.record_path            : Path for recordings made with the 'Record' button
%   P.record_num_frames      : Default number of frames per recording
%   P.burst_*                : Settings of the 'Burst' button, see below and docs/burst.md
%
% Advanced options:
%   P.num_accumulations      : Number of RF accumulations. Increases SNR but
%                               lowers FPS and may cause clipping
%   P.use_adaptive_xwave_angle : If true, xWave angles are adapted based on max
%                                 requested imaging depth
%   P.use_half_pitch_scanning  : Enables half-pitch scanning for finer sampling,
%                                 at cost of max frame rate.
%   P.transmit_frequency       : Transducer transmit frequency [MHz]
%   P.use_cpu_beamformer       : Use the slow MATLAB stand-in xw_beamform_cpu
%                                 instead of the compiled GPU beamformer. Default:
%                                 true if XAM_CPU_BEAMFORMER=1 is set.
%
% Dependent parameters (computed from above):
%   P.half_aperture_size     : Half the number of active elements in transmit aperture
%   P.ray_positions          : Transmit ray locations (element indices).
%                               With half-pitch scanning enabled, indices fall
%                               between neighboring elements.
%   P.ray_positions_mm       : Physical positions [mm] of transmit rays in element coordinates
%
% -------------------------------------------------------------------------
% Output Data (struct BFData)
% -------------------------------------------------------------------------
% Data is beamformed on a fixed image grid of P.x_axis and P.z_axis.
% After beamforming, data is returned in the struct BFData with fields:
%
%   BFData.PW       : B-mode image (complex IQ) reconstructed from plane-wave
%                     data [pixels: depth × lateral]
%
%   BFData.xAM      : xAM image (complex IQ) highlighting GV-specific contrast
%                     [pixels: depth × lateral]
%
%   BFData.TimeTag  : Time stamp of recorded data (numeric)
%
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
addpath(fullfile(repo_root, 'dependencies', 'utilities'))
addpath(fullfile(repo_root, 'dependencies', 'utilities', 'save'))

% VSX must run from the root of the Verasonics software. Find it from the
% activated software on the path, so no installation path is hard-coded.
vantage_root = fileparts(which('VSX'));
assert(~isempty(vantage_root), ['Verasonics software not found: run activate in the ' ...
    'root folder of the Verasonics software first (or use run_xam.sh).'])
cd(vantage_root);

%% =============================================================================
% SETUP ACQUISITION PARAMETERS
% ==============================================================================
Trans.name = 'L22-14vX'; % tested transducers are L22-14vX / L11-5v

P.image_start_depth_mm = 0; % start depth [mm]
P.image_end_depth_mm = 10; % end depth [mm]

P.xwave_angles = 17; % xWave angle in degrees

P.speed_of_sound = 1480; % agar/water 1480 m/s, tissue 1540 m/s
P.image_voltage = 2.5; % set to safe number to avoid collapse

P.aperture_size_min = 48; % min number of elements in active aperture (48 for wide FOV)
P.aperture_size_max = 64; % max number of elements in active aperture

P.transmit_apodization = 'tukey'; % Apodization to avoid edge waves. Options: none/kaiser/hamming/tukey
P.fps = 2; % acquisition frame rate in [Hz]
if ~isempty(getenv('XAM_FPS')), P.fps = str2double(getenv('XAM_FPS')); end % tests/run_tests.sh --fps

P.save_path = fullfile(repo_root, 'data'); % default path for data saving
if ~isempty(getenv('XAM_DATA_PATH')); P.save_path = getenv('XAM_DATA_PATH'); end % e.g. set by tests/run_tests.sh
P.record_path = P.save_path; % path for recordings ('Record' button), put on a fast (NVMe) drive
P.record_num_frames = 20; % default number of frames per recording

% Voltage sweep ('Voltage sweep' button), configured with run_xam.sh --sweep. Empty = no sweep.
P.sweep_voltages = xw_parse_voltages(getenv('XAM_SWEEP_VOLTAGES')); % [V], e.g. 1.6:0.4:6
P.sweep_passes = 2; % passes through the voltages (pass 2 shows whether GVs collapsed in pass 1)
P.sweep_frames = 5; % frames recorded and measured per voltage
P.sweep_save_mode = 'images'; % saved per voltage: 'images' (~0.6 MB/frame) or 'rf' (~190 MB/frame)
if ~isempty(getenv('XAM_SWEEP_SAVE')); P.sweep_save_mode = getenv('XAM_SWEEP_SAVE'); end
if ~isempty(getenv('XAM_SWEEP_FRAMES')); P.sweep_frames = str2double(getenv('XAM_SWEEP_FRAMES')); end
P.sweep_settle_frames = 2; % frames discarded after each voltage change
P.sweep_settle_s = 1; % minimum settle time after a voltage increase [s]
P.sweep_settle_s_down = 3; % minimum settle time after a voltage decrease [s]
P.sweep_max_voltage = 25; % sweep refuses voltages above this [V] (L22-14vX limit is 30 V)

% Burst ('Burst' button): frames at the imaging voltage, frames at the burst voltage, frames at the imaging voltage.
% The burst voltage is TPC profile 2 (VSX slider 'High Voltage P2'), the imaging voltage profile 1 ('High Voltage P1').
% The burst uses focused transmits (not xWaves) and its own, higher frame rate, as the BURST_L22_14v script.
P.burst_voltage = 25; % [V] (L22-14vX limit is 30 V, see Trans.maxHighVoltage)
P.burst_pre_frames = 10;
P.burst_collapse_frames = 46;
P.burst_post_frames = 0;
P.burst_start_depth_mm = 2; % image depth of the burst [mm]
P.burst_end_depth_mm = 14;
P.burst_num_tx = 40; % elements in the transmit aperture. The rays are all positions of the aperture
P.burst_focus_mm = 6; % transmit focus [mm]
P.burst_tw_half_cycles = 7; % length of the transmit pulse in half cycles
P.burst_frame_delay_factor = 10; % time between frames, in times the time between acquisitions
P.burst_preview_every = 4; % preview every n-th frame of the burst while it runs, 0 = no preview
P.burst_confirm = true; % ask for confirmation before a burst: it collapses gas vesicles irreversibly
P.burst_settle_us = 8000; % time reserved for a change of the voltage [us] (0.8 to 8 ms, depending on the voltage step)
% tests/run_tests.sh uses a short burst at a safe voltage and no confirmation
if ~isempty(getenv('XAM_BURST_VOLTAGE')), P.burst_voltage = str2double(getenv('XAM_BURST_VOLTAGE')); end
if ~isempty(getenv('XAM_BURST_FRAMES')), burst_frames = str2double(strsplit(getenv('XAM_BURST_FRAMES'), ',')); [P.burst_pre_frames, P.burst_collapse_frames, P.burst_post_frames] = deal(burst_frames(1), burst_frames(2), burst_frames(3)); end
if strcmp(getenv('XAM_BURST_CONFIRM'), '0'), P.burst_confirm = false; end

%% =============================================================================
% INPUT VALIDATION
% ==============================================================================
assert(P.image_end_depth_mm >= P.image_start_depth_mm, 'Image end depth must be larger than start depth. Recommended start = 0, end = 10mm')
assert(P.aperture_size_min < P.aperture_size_max, 'Min aperture size must be smaller than max aperture size. Recommended min = 33, max = 64')
assert(all(P.sweep_voltages <= P.sweep_max_voltage), 'Sweep voltages must not exceed P.sweep_max_voltage = %g V', P.sweep_max_voltage)
assert(all(P.sweep_voltages >= 1.6), 'Sweep voltages must be at least 1.6 V (Vantage minimum)')
assert(ismember(P.sweep_save_mode, {'images', 'rf'}), 'P.sweep_save_mode must be ''images'' or ''rf''')
BP = xw_burst_plan(P.burst_pre_frames, P.burst_collapse_frames, P.burst_post_frames); % frames of a burst
assert(P.burst_voltage >= 1.6, 'Burst voltage must be at least 1.6 V (Vantage minimum)')
assert(P.burst_end_depth_mm > P.burst_start_depth_mm, 'Burst end depth must be larger than start depth')
assert(P.burst_preview_every >= 0 && P.burst_preview_every == round(P.burst_preview_every), 'P.burst_preview_every must be a non-negative integer')
assert(isfinite(P.sweep_frames) && P.sweep_frames >= 1 && P.sweep_frames == round(P.sweep_frames), 'Sweep frames per voltage must be a positive integer')

%% =============================================================================
% TRANSDUCER PARAMETERS
% ==============================================================================

% Define Trans structure array
Trans.units = 'mm';
Trans = computeTrans(Trans);
assert(P.burst_voltage <= Trans.maxHighVoltage, 'Burst voltage %g V is above the limit of %s of %g V', P.burst_voltage, Trans.name, Trans.maxHighVoltage)

%% =============================================================================
% SYSTEM PARAMETERS
% ==============================================================================
% Define system parameters
Resource.Parameters.numTransmit = 128; % number of transmit channels
Resource.Parameters.numRcvChannels = 128; % number of receive channels
Resource.Parameters.speedOfSound = P.speed_of_sound; % speed of sound [m/s]
Resource.Parameters.verbose = 1; % controls output warnings
Resource.Parameters.speedCorrectionFactor = 1.0;
Resource.Parameters.simulateMode = double(strcmp(getenv('XAM_SIMULATE'), '1')); % 1: simulation, 0: hardware (run_xam.sh --sim sets 1)
Resource.Parameters.fakeScanhead = 0;
Resource.VDAS.dmaTimeout = 1000 * 4; % 4 seconds
Resource.VDAS.acqTimeTagEnable = 1;
Resource.Parameters.waitForProcessing = 1;

% Compute and set dependent parameters

% Advanced options
P.num_accumulations = 1; % if >1, will accumulate RF data on the device. Keep low to avoid clipping! Lowers max FPS!
P.use_adaptive_xwave_angle = true; % if true updates the xWave Angles dependent on the  imaging depth
P.use_half_pitch_scanning = true;
P.transmit_frequency = Trans.frequency; % transducer transmit frequency [MHz]
P.use_cpu_beamformer = strcmp(getenv('XAM_CPU_BEAMFORMER'), '1'); % slow MATLAB beamformer instead of the GPU one

P.num_pulses = 3; % number of pulses in xAM pulse sequence, hardcoded
P.rf_datatype = 'int16'; % RF data format: 'int16', or 'half' (16 bit floating point: more dynamic range, accumulation of up to 512 acquisitions without overflow)
if ~isempty(getenv('XAM_RF_DATATYPE')), P.rf_datatype = getenv('XAM_RF_DATATYPE'); end % tests/run_tests.sh --half
assert(ismember(P.rf_datatype, {'int16', 'half'}), 'P.rf_datatype must be ''int16'' or ''half''');
P.num_chunks = 8; % the frame is transferred and reconstructed in this many groups of rays, while the next rays are acquired (1 = whole frame at the end). Needs num_accumulations = 1.
P.timetag_enabled = 1; % debug option, see time tags of frames
P.num_rf_frames = 4; % must be >4 or even number, don't change
P.beamform_image_modes = {'PW', 'xAM'}; % PW = bf(\)+bf(/), xBmode = bf(X), xAM = bf(X-\-/)

% choose rays for pitch or pitch/2 scanning
step = 1 / (P.use_half_pitch_scanning + 1);
P.half_aperture_size = (P.aperture_size_min - rem(P.aperture_size_min, 2)) / 2; % number of active elements in half transmit aperture
P.ray_positions = ceil(P.aperture_size_min / 2) + 1:step:Resource.Parameters.numTransmit - floor(P.aperture_size_min / 2); % pitch scanning
P.ray_positions_mm = interp1(1:Trans.numelements, Trans.ElementPos(:, 1), P.ray_positions);
P.num_rays = numel(P.ray_positions);

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
% and reconstructed while the next rays are acquired)
P.rf_layout = 'ray-major';
if P.num_accumulations > 1 && P.num_chunks > 1
    warning('num_chunks is set to 1: chunks need num_accumulations = 1');
end
if P.num_accumulations > 1, P.num_chunks = 1; end
P.num_chunks = numel(xw_chunk_rays(P.num_rays, P.num_chunks));

% specify Media object
pt1;
Media.function = 'movePoints';

%% =============================================================================
% RESOURE BUFFERS
% ==============================================================================

% determine demod frequency, and compute Nz_RF
TxFreq = 250 ./ (2 .* ((6:197).'));
TxFreqValid = TxFreq(2 .* TxFreq < 3.5 & TxFreq > 1.5); % depends on Trans.Bandwidth [1.5 3.5] for P4-1
demodFreqsValid = TxFreq(rem(250, TxFreq * 4) == 0);
[~, idx] = min(abs(Trans.frequency - demodFreqsValid));
demodFrequency = demodFreqsValid(idx);
% fprintf('\tTX    FREQ: %.3f MHz\n', Trans.frequency)
% fprintf('\tDEMOD FREQ: %.3f MHz\n', demodFrequency)

maxAcqLength = ceil(sqrt(P.image_end_depth_mm ^ 2 + ((Trans.numelements - 1) * Trans.spacingMm) ^ 2)); % [mm]
maxAcqLengthWvl = maxAcqLength * P.scale_mm2wvl;
P.Nz_RF = (ceil(maxAcqLengthWvl * 2 * 4 * demodFrequency / Trans.frequency / 128) * 128); %2*4*enddepth*factor (beam forming factor)

% allocate resources
Resource.RcvBuffer(1).datatype = 'int16';
Resource.RcvBuffer(1).rowsPerFrame = P.num_rays * P.num_angles * P.num_pulses * P.Nz_RF;
Resource.RcvBuffer(1).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(1).numFrames = P.num_rf_frames;

% RcvProfile.LnaZinSel = 31; % turn on high Z-state, increase sensitivity

%% Timing parameters
P.num_tx_per_frame = P.num_accumulations * P.num_angles * P.num_pulses * P.num_rays;
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

% Specify TX structure array
% Transmit centered on element n in the array for event n.
TX = repmat(struct('waveform', 1, ...
    'Origin', [0.0, 0.0, 0.0], ...
    'Steer', [0.0, 0.0], ...
    'Apod', zeros(1, Trans.numelements), ...
    'focus', 0, ...
    'Delay', zeros(1, Trans.numelements)), ...
    1, P.num_pulses * P.num_angles * P.num_rays);

TPC(1).hv = P.image_voltage; % imaging voltage
TPC(2).hv = P.burst_voltage; % burst voltage, used by the burst events

% dummy transmit without active elements, to change the TPC profile between frames
TX(end + 1) = TX(1);
TX(end).Apod = zeros(1, Trans.numelements);
TX(end).Delay = zeros(1, Trans.numelements);
P.dummy_tx = numel(TX);

% Specify Receive structure arrays.
P.use_accumulation = P.num_accumulations > 1;
nRcvObj_p_accum = P.num_pulses * P.num_rays * P.num_angles;
nRcvObj_p_frame = nRcvObj_p_accum * (P.use_accumulation + 1);
Receive = repmat(struct('Apod', zeros(1, Trans.numelements), ...
    'startDepth', 0, ... % P.image_start_depth_mm * P.scale_mm2wvl, ...
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

% Receive structures are ordered by acquisition number within a frame: for every ray the 3 pulses
% (X, L, R) with all angles each. rcv_index gives the position in the Receive array (pulse 0..2,
% accum = 1 for the structures that accumulate onto the first ones), rcv_acq_num the acqNum
% (the position of the acquisition in the frame of the receive buffer).
rcv_acq_num = @(ray, pulse, angle) ((ray - 1) * P.num_pulses + pulse) * P.num_angles + angle;
rcv_index = @(ray, pulse, angle, frame, accum) rcv_acq_num(ray, pulse, angle) ...
    + (frame - 1) * nRcvObj_p_accum + accum * nRcvObj_p_accum * P.num_rf_frames;

% Set event specific Receive and TX attributes.
% Compute transmit delays
P.ray_angle = zeros(P.num_angles, P.num_rays); % xWave angles per ray
for idx_ray = 1:P.num_rays
    for idx_angle = 1:P.num_angles
        idx_tx = idx_angle + (idx_ray - 1) * P.num_angles;
        TX = xw_setup_build_transmit(TX, idx_tx, idx_ray, idx_angle, Trans, P);

        for idx_frame = 1:P.num_rf_frames
            for idx_pulse = 0:P.num_pulses - 1 % X pulse, left active aperture, right active aperture
                idx = rcv_index(idx_ray, idx_pulse, idx_angle, idx_frame, 0);

                if (idx_ray == 1 && idx_angle == 1 && idx_pulse == 0)
                    Receive(idx).callMediaFunc = 1;
                end

                Receive(idx).Apod(:) = 1.0; % activate all elements
                Receive(idx).mode = 0;
                Receive(idx).framenum = idx_frame;
                Receive(idx).acqNum = rcv_acq_num(idx_ray, idx_pulse, idx_angle);

                if P.use_accumulation
                    idx = rcv_index(idx_ray, idx_pulse, idx_angle, idx_frame, 1);

                    Receive(idx).mode = 1;
                    Receive(idx).Apod(:) = 1.0; % activate all elements
                    Receive(idx).framenum = idx_frame;
                    Receive(idx).acqNum = rcv_acq_num(idx_ray, idx_pulse, idx_angle);
                end
            end
        end
    end
end

%% =============================================================================
% TIME GAIN CONTROL
% ==============================================================================
% Specify TGC Waveform structure (time-gain-compensation)
TGC(1).CntrlPts = 800 * ones(1, 8); % 1023 is max gain
TGC(1).rangeMax = P.image_end_depth_mm * P.scale_mm2wvl; % in wavelengths
TGC(1).Waveform = computeTGCWaveform(TGC(1));

%% =============================================================================
% BURST: FOCUSED TRANSMITS, RECEIVE BUFFER AND RECONSTRUCTION
% ==============================================================================
% The burst is acquired and reconstructed with the Verasonics reconstruction, in its own receive buffer
% that holds all frames of the burst, see xw_setup_burst. Transmit waveform 2, TGC 2, receive buffer 2.
SB = xw_setup_burst(P, Trans, BP.num_frames, numel(TX), numel(Receive));
TX = [TX, SB.TX];
Receive = [Receive, SB.Receive];
TW(2) = SB.TW;
TGC(2) = SB.TGC;
PData = SB.PData;
Recon = SB.Recon;
ReconInfo = SB.ReconInfo;
Resource.RcvBuffer(2).datatype = 'int16';
Resource.RcvBuffer(2).rowsPerFrame = SB.rows_per_frame;
Resource.RcvBuffer(2).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(2).numFrames = BP.num_frames + mod(BP.num_frames, 2); % VSX needs 1 or an even number of frames
Resource.InterBuffer(1).numFrames = 1;
Resource.ImageBuffer(1).numFrames = BP.num_frames; % reconstructed frames of the burst
Resource.ImageBuffer(2).numFrames = 1; % preview
P.burst_num_rays = SB.num_rays;
P.burst_x_axis = SB.x_axis; % image axes [mm]
P.burst_z_axis = SB.z_axis;
P.burst_ttna = 3 * P.burst_end_depth_mm / P.speed_of_sound * 2 * 1e3; % time between acquisitions [us]
P.burst_ttna_frame = P.burst_frame_delay_factor * P.burst_ttna; % time after the last acquisition of a frame [us]
P.burst_frame_period = (P.burst_ttna * 3 * SB.num_rays + P.burst_ttna_frame) * 1e-6; % nominal time between frames [s]

%% =============================================================================
% PROCESS FUNCTIONS
% ==============================================================================

% specify external processing event
np = 1;
PN.image_reconstruct = np;
Process(np).classname = 'External';
Process(np).method = 'xw_beamform_run';
Process(np).Parameters = {'srcbuffer', 'receive', ...
    'srcbufnum', 1, ...
    'srcframenum', -1, ...
    'dstbuffer', 'none'};
np = np + 1;

% with chunks: one process per group of rays, reconstructing when these have been transferred
PN.image_reconstruct_chunk = zeros(1, P.num_chunks);
EF = struct('FunctionName', {}, 'FunctionHandle', {});
for idx_chunk = 1:P.num_chunks * (P.num_chunks > 1)
    PN.image_reconstruct_chunk(idx_chunk) = np;
    Process(np).classname = 'External';
    Process(np).method = sprintf('xw_beamform_chunk%02i', idx_chunk);
    Process(np).Parameters = {'srcbuffer', 'receive', ...
        'srcbufnum', 1, ...
        'srcframenum', -1, ...
        'dstbuffer', 'none'};
    EF(idx_chunk) = struct('FunctionName', Process(np).method, ...
        'FunctionHandle', @(RData) xw_beamform_run(RData, idx_chunk));
    np = np + 1;
end

PN.image_reconstruct_init = np;
Process(np).classname = 'External';
Process(np).method = 'xw_beamform_run';
Process(np).Parameters = {'srcbuffer', 'receive', ...
    'srcbufnum', 1, ...
    'srcframenum', 1, ...
    'dstbuffer', 'none'};
np = np + 1;

PN.image_display = np;
Process(np).classname = 'External';
Process(np).method = 'xw_plot';
Process(np).Parameters = {'srcbuffer', 'none', ...
    'dstbuffer', 'none'};
np = np + 1;

% burst: preview of the latest frame, saving of the images of each frame, and the end of the burst
PN.burst_preview = np;
Process(np).classname = 'External';
Process(np).method = 'xw_burst_preview';
Process(np).Parameters = {'srcbuffer', 'image', ...
    'srcbufnum', 2, ...
    'srcframenum', -1, ...
    'dstbuffer', 'none'};
np = np + 1;

PN.burst_save = zeros(1, BP.num_frames);
for idx_frame = 1:BP.num_frames
    PN.burst_save(idx_frame) = np;
    Process(np).classname = 'External';
    Process(np).method = 'xw_burst_save_image';
    Process(np).Parameters = {'srcbuffer', 'image', ...
        'srcbufnum', 1, ...
        'srcframenum', idx_frame, ...
        'dstbuffer', 'none'};
    np = np + 1;
end

PN.burst_finish = np;
Process(np).classname = 'External';
Process(np).method = 'xw_burst_finish';
Process(np).Parameters = {'srcbuffer', 'none', ...
    'dstbuffer', 'none'};
np = np + 1;

PN.saveAcqPars = np;
Process(np).classname = 'External'; % process structure for 1st Doppler ensemble
Process(np).method = 'xw_sequence_save_acquisition_parameters';
Process(np).Parameters = {'srcbuffer', 'none', ... % name of buffer to process.
    'dstbuffer', 'none'};
np = np + 1;

%% =============================================================================
% SEQUENCE CONTROL
% ==============================================================================

% Specify SeqControl structure arrays.
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
SeqControl(5).command = 'loopCnt';
SeqControl(5).argument = (P.num_accumulations - 1);
SC.loopCnt = 5;
SeqControl(6).command = 'timeToNextAcq';
P.ttna_frame = 1e6 / P.fps - P.ttna * (P.num_tx_per_frame);
assert(P.ttna_frame > P.ttna, 'frame rate too high! Max is %.2f Hz', P.max_framerate)
SeqControl(6).argument = P.ttna_frame; %  4e6; % 4 seconds max! in microseconds!
SC.ttna_frame = 6;

SeqControl(7).command = 'sync';
SeqControl(7).argument = 1000 * 4;
SC.sync = 7;

SeqControl(8).command = 'timeToNextAcq';
SeqControl(8).argument = P.burst_ttna; % between the acquisitions of a burst
SC.ttna_burst = 8;
SeqControl(9).command = 'timeToNextAcq';
SeqControl(9).argument = P.burst_settle_us; % after a change of the voltage
SC.tpc_settle = 9;
SeqControl(10).command = 'setTPCProfile';
SeqControl(10).argument = 1; % imaging voltage
SeqControl(10).condition = 'next';
SC.tpc_imaging = 10;
SeqControl(11).command = 'setTPCProfile';
SeqControl(11).argument = 2; % burst voltage
SeqControl(11).condition = 'next';
SC.tpc_burst = 11;
SeqControl(12).command = 'jump';
SeqControl(12).argument = []; % set later, to EN.StartEvent
SC.jump_start = 12;
SeqControl(13).command = 'timeToNextAcq';
SeqControl(13).argument = P.burst_ttna_frame; % between the frames of a burst
SC.ttna_burst_frame = 13;
tpc_sc = [SC.tpc_imaging, SC.tpc_burst]; % setTPCProfile of TPC profile 1, 2

nsc = length(SeqControl) + 1;

%% =============================================================================
% EVENT STRUCTURES
% ==============================================================================

% Specify Event structure arrays.
n = 1;

Event(n).info = 'initialize beamformer';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 0;
Event(n).process = PN.image_reconstruct_init;
Event(n).seqControl = SC.matlab;
n = n + 1;

Event(n).info = 'initialize beamformer';
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

% when the sequence is started, and after a burst: imaging voltage (TPC profile 1)
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

chunk_rays = xw_chunk_rays(P.num_rays, P.num_chunks);
for idx_frame = 1:P.num_rf_frames
  for idx_chunk = 1:P.num_chunks
    for idx_ray = chunk_rays{idx_chunk} % 1st set of acquisitions
        for idx_angle = 1:P.num_angles
            idx_TX = idx_angle + (idx_ray - 1) * P.num_angles;
            Event(n).info = sprintf('Acquire X R%03i A%02i F%02i', idx_ray, idx_angle, idx_frame);
            Event(n).tx = idx_TX;
            Event(n).rcv = rcv_index(idx_ray, 0, idx_angle, idx_frame, 0);
            Event(n).recon = 0;
            Event(n).process = 0;
            Event(n).seqControl = SC.ttna; % Time between acquisitions
            n = n + 1;

            Event(n).info = sprintf('Acquire L R%03i A%02i F%02i', idx_ray, idx_angle, idx_frame);
            Event(n).tx = idx_TX + P.num_rays * P.num_angles;
            Event(n).rcv = rcv_index(idx_ray, 1, idx_angle, idx_frame, 0);
            Event(n).recon = 0;
            Event(n).process = 0;
            Event(n).seqControl = SC.ttna; % Time between acquisitions
            n = n + 1;

            Event(n).info = sprintf('Acquire R R%03i A%02i F%02i', idx_ray, idx_angle, idx_frame);
            Event(n).tx = idx_TX + 2 * P.num_rays * P.num_angles;
            Event(n).rcv = rcv_index(idx_ray, 2, idx_angle, idx_frame, 0);
            Event(n).recon = 0;
            Event(n).process = 0;
            Event(n).seqControl = SC.ttna; % Time between acquisitions
            n = n + 1;
        end
    end

    if idx_chunk == P.num_chunks && ~P.use_accumulation
        Event(n - 1).seqControl = SC.ttna_frame; % Time between acquisitions
    end
    if P.num_chunks > 1
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
  end

    if P.use_accumulation
        Event(n).info = 'Set loop count for number of accumulates.';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = SC.loopCnt;
        n = n + 1;

        Event(n).info = 'Jump to end of accumulate events for loop count test.';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc;
        SeqControl(nsc).command = 'jump'; % Argument set below.
        nsc = nsc + 1;
        n = n + 1;

        nstart = n;

        % and accumulation acqs
        for idx_ray = 1:P.num_rays % 1st set of acquisitions
            for idx_angle = 1:P.num_angles
                idx_TX = idx_angle + (idx_ray - 1) * P.num_angles;
                Event(n).info = sprintf('Acquire X R%03i A%02i F%02i accum', idx_ray, idx_angle, idx_frame);
                Event(n).tx = idx_TX;
                Event(n).rcv = rcv_index(idx_ray, 0, idx_angle, idx_frame, 1); % use next receive structure
                Event(n).recon = 0;
                Event(n).process = 0;
                Event(n).seqControl = SC.ttna; % Time between acquisitions
                n = n + 1;

                Event(n).info = sprintf('Acquire L R%03i A%02i F%02i accum', idx_ray, idx_angle, idx_frame);
                Event(n).tx = idx_TX + P.num_rays * P.num_angles;
                Event(n).rcv = rcv_index(idx_ray, 1, idx_angle, idx_frame, 1); % use next receive structure
                Event(n).recon = 0;
                Event(n).process = 0;
                Event(n).seqControl = SC.ttna; % Time between acquisitions
                n = n + 1;

                Event(n).info = sprintf('Acquire R R%03i A%02i F%02i accum', idx_ray, idx_angle, idx_frame);
                Event(n).tx = idx_TX + 2 * P.num_rays * P.num_angles;
                Event(n).rcv = rcv_index(idx_ray, 2, idx_angle, idx_frame, 1); % use next receive structure
                Event(n).recon = 0;
                Event(n).process = 0;
                Event(n).seqControl = SC.ttna; % Time between acquisitions
                n = n + 1;
            end
        end

        SeqControl(nsc - 1).argument = n;
        Event(n).info = 'Test loop count - if nz, jmp back to start of accumulates.';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc;
        SeqControl(nsc).command = 'loopTst';
        SeqControl(nsc).argument = nstart;
        nsc = nsc + 1;
        n = n + 1;

        Event(n).info = 'dummy tx';
        Event(n).tx = 1;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = SC.ttna_frame; % Time between acquisitions
        n = n + 1;
    end

    if P.num_chunks == 1 % otherwise transferred and reconstructed per chunk, above
        Event(n).info = 'Transfer frame to host buffer';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = [nsc];
        SeqControl(nsc).command = 'transferToHost'; % transfer frame to host buffer
        nsc = nsc + 1;
        n = n + 1;

        Event(n).info = 'waitForTransferComplete';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc; % waitForTransferComplete
        n = n + 1;
        % set waitTransfer to reference last SeqControl
        SeqControl(nsc).command = 'waitForTransferComplete'; % wait for transfer complete, needed for large superframes
        SeqControl(nsc).argument = nsc - 1;
        nsc = nsc + 1;

        Event(n).info = 'Image Reconstruct';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = PN.image_reconstruct;
        Event(n).seqControl = 0; %
        n = n + 1;

        Event(n).info = 'markTransferProcessed';
        Event(n).tx = 0;
        Event(n).rcv = 0;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = nsc; % markTransferProcessed
        n = n + 1;
        % set waitTransfer to reference last SeqControl
        SeqControl(nsc).command = 'markTransferProcessed'; % wait for transfer complete, needed for large superframes
        SeqControl(nsc).argument = nsc - 2;
        nsc = nsc + 1;
    end

    Event(n).info = 'Image Display';
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = 0;
    Event(n).process = PN.image_display;
    Event(n).seqControl = SC.matlab; %
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
% transferred to the receive buffer 2 that holds all frames. The images are reconstructed (Verasonics
% reconstruction) and saved all at the end of the burst, after the last acquisition.
%
% Resource.Parameters.waitForProcessing = 1 (needed for the acquisition loop above) makes the hardware
% wait, before each transfer, until the software has asked for the latest frame (with a frame number -1).
% During the burst this is done with a reconstruction of the latest frame after every frame: of one ray
% (fast) or, for every P.burst_preview_every-th frame, of all rays, which is shown in the preview. The
% preview takes some time, so the acquisition waits for it: set P.burst_preview_every = 0 for the fastest burst.
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

    for idx_ray = 1:SB.num_rays
        for idx_pulse = 1:3 % full aperture, odd elements off, even elements off
            Event(n).info = sprintf('Burst: acquire R%03i P%i F%03i', idx_ray, idx_pulse, idx_frame);
            Event(n).tx = SB.tx_index(idx_pulse, idx_ray);
            Event(n).rcv = SB.rcv_index(idx_pulse, idx_ray, idx_frame);
            Event(n).recon = 0;
            Event(n).process = 0;
            Event(n).seqControl = SC.ttna_burst;
            n = n + 1;
        end
    end
    Event(n - 1).seqControl = [SC.ttna_burst_frame, tth_sc(idx_frame)];
    SeqControl(tth_sc(idx_frame)).command = 'transferToHost'; % transfer the frame to the host buffer

    % ask for the latest frame, see above
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).seqControl = 0;
    if P.burst_preview_every > 0 && mod(idx_frame, P.burst_preview_every) == 0
        Event(n).info = sprintf('Burst: preview after frame %i', idx_frame);
        Event(n).recon = SB.recon_preview;
        Event(n).process = PN.burst_preview;
    else
        Event(n).info = sprintf('Burst: request latest frame after frame %i', idx_frame);
        Event(n).recon = SB.recon_request;
        Event(n).process = 0;
    end
    n = n + 1;
end

% reconstruct and save all frames, one after the other. A reconstruction waits for the transfer of its frame
for idx_frame = 1:BP.num_frames
    Event(n).info = sprintf('Burst: reconstruct and save frame %i', idx_frame);
    Event(n).tx = 0;
    Event(n).rcv = 0;
    Event(n).recon = SB.recon_final(idx_frame);
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

% voltage sweep, only when configured (run_xam.sh --sweep); press again to stop
if ~isempty(P.sweep_voltages)
    UI(n_ui).Control = {'UserB2', 'Style', 'VsPushButton', 'Label', 'Voltage sweep'};
    UI(n_ui).Callback = {'xw_sweep_start()'};
    n_ui = n_ui + 1;
end
XWSweep = struct('active', false); % sweep state, see xw_sweep_start

% configure saveDataMenu
P.matfile_file_name = 'xAM_imaging.mat';
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
