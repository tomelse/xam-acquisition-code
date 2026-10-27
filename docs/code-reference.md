---
title: Code reference
nav_order: 13
---

# Code reference

The sequence shares state with VSX through the MATLAB base workspace: `P`,
`UISTATES`, `BFData`, `XWRecord` and the Verasonics structs are read and
written with `evalin('base', …)` / `assignin('base', …)`.

## Main script

| File | Description |
| --- | --- |
| `run_xam.sh` | Terminal launcher: parses the options (`--sweep`, `--save`, `--sim`, …), passes them to MATLAB as `XAM_*` environment variables, and runs `xAM_imaging.m`. |
| `xAM_imaging.m` | Sets parameters, builds the Verasonics structs (`Trans`, `TW`, `TX`, `Receive`, `TGC`, `Process`, `SeqControl`, `Event`, `UI`), saves them to `MatFiles/xAM_imaging.mat` and starts `VSX`. |

## `examples`

| File | Description |
| --- | --- |
| `reconstruct_rf.m` | Example script: reconstructs a saved RF recording or snapshot frame by frame, identically to the live view, and shows the image stack. A starting point for offline processing. |

## `dependencies/sequence`: setup and GUI callbacks

| Function | Description |
| --- | --- |
| `xw_setup_build_transmit` | Builds the X, L and R `TX` structures for one ray and angle: aperture size, adaptive angle, apodization. |
| `xw_setup_compute_delays` | Transmit delays and channels for X, L and R, for integer and half-element bisectors. |
| `xw_setup_timetag` | Enables hardware time tagging (hardware only). |
| `xw_sequence_start` | **Start Seq.**: starts the hardware at the first acquisition event (`EN.StartEvent`, which sets the imaging voltage) and unfreezes. |
| `xw_sequence_save_acquisition_parameters` | Saves the sequence structs to `<save_path>/<name>_ACQ_PARAMETERS.mat`, or to a given path. |
| `xw_change_persistence` | **Persistence** slider. |
| `xw_change_dr` | **DR B-Mode** and **DR xAM** sliders. |
| `xw_change_save_mode` | **Save mode** switch: sets `UISTATES.save_mode` to `'images'` or `'rf'`. |
| `xw_change_record_frames` | **Rec. frames** slider. |
| `xw_save_data` | **Save Data**: presets the save menu for the save mode and opens it. |
| `xw_sweep_start` | **Voltage sweep**: starts a voltage sweep, or stops a running one. |
| `xw_sweep_frame` | Called for every frame from `xw_beamform_run`; settles, records and measures each voltage step. |
| `xw_sweep_next_step` | Sets the voltage of the next step and its settle time. |
| `xw_sweep_set_voltage` | Sets the TPC profile 1 voltage at runtime (as the **High Voltage P1** slider does) and updates the slider. |
| `xw_sweep_finish` | Restores the voltage, saves `sweep_results.mat` and plots the result. |
| `xw_burst_start` | **Burst**: checks that a burst can start, asks for confirmation, and restarts the sequence at the burst events (`EN.Burst`). |
| `xw_burst_plan` | Voltage profile (imaging / burst) of every frame of a burst, and where the sequence switches it. |
| `xw_setup_burst` | Focused transmits (3 pulses per ray), receive structures and Verasonics reconstruction (`PData`, `Recon`, `ReconInfo`) of the burst. |
| `xw_burst_difference` | Burst analysis: frame 11 (first at the burst voltage) minus the mean of the subsequent frames at that voltage (shown by `xw_burst_finish`). |
| `xw_burst_preview`, `xw_burst_save_image`, `xw_burst_finish` | Process functions of the burst events: preview of the latest frame, keep each reconstructed image, and save the burst and return to live imaging. |
| `xw_burst_update_button` | Enables or disables **Burst** (not during a recording, sweep, burst or freeze). |
| `xw_set_start_event` | Restarts the sequence at a given event (`set&Run`), used by **Start Seq.** and the burst. |
| `xw_record_begin` | Starts a recording of a given mode, frame count and folder (used by **Record** and the sweep). |
| `xw_record_start` | **Record**: checks disk space, creates the recording folder, starts the background threads and the recording (or stops a running one). |
| `xw_record_frame` | Called for every frame from `xw_beamform_run`; starts a background write of the RF frame (`frame_#####.bin`) or saves `frame_#####.mat`. Limits the number of writes still running. |
| `xw_record_write_frame` | Writes one RF frame to its own file; runs on a `backgroundPool` thread. |
| `xw_record_stop` | Ends a recording; the final steps run once all background writes have finished, without blocking acquisition. |
| `xw_record_save_info` | Writes `recording_info.mat`. |
| `xw_record_finish` | Checks which frames were written, writes the final `recording_info.mat`, reports the frame rate. |

## `dependencies/reconstruct`: beamforming

| Function | Description |
| --- | --- |
| `xw_beamform_run` | External process function called per frame: reconstructs the frame (`xw_reconstruct_frame`), records it, advances a sweep, applies persistence and stores `BFData`. |
| `xw_reconstruct_setup` | Image grid, delay lookup tables and beamformer choice for a sequence. Shared by the live view and offline reconstruction. |
| `xw_reconstruct_chunk`, `xw_reconstruct_chunks`, `xw_chunk_rays` | Reconstruct a group of rays (chunk) as soon as it has been transferred; build the chunks with their delay tables; split the rays into chunks. |
| `xw_half2single` (in `utilities`) | Converts half RF data (stored as int16 bit patterns) to single. |
| `xw_reconstruct_rays` | Splits the X/L/R pulses of the given rays (for either receive buffer layout) and beamforms them; used by the two functions above and below. |
| `xw_reconstruct_frame` | Reconstructs one frame of RF data: splits X/L/R, forms `X − L − R`, beamforms `PW` (and `xBmode`) and `xAM`. Shared by the live view and offline reconstruction. |
| `xw_beamform_gpu` | GPU beamformer (`gpuArray`), the default. Same algorithm as `xw_beamform_cpu`; keeps the LUTs on the GPU between calls. |
| `xw_beamform_gpu_available` | Checks for the Parallel Computing Toolbox and a usable GPU; enables CUDA forward compatibility for GPUs newer than MATLAB. |
| `xw_beamform_cpu` | Slow reference beamformer, no GPU needed (`--cpu-beamformer`). |
| `xw_beamform_compute_LUT` | Transmit and receive delay lookup tables, including the f-number mask, waveform peak and lens corrections. |
| `MLBFXWave.m` | Documentation of the beamformer interface (`BFIQ = f(BFC, RF, LUT_T, LUT_R)`) shared by all beamformers. A compiled `MLBFXWave`, if on the path, is used instead of `xw_beamform_cuda`. |

## `dependencies/display`

| Function | Description |
| --- | --- |
| `xw_plot` | Live image window: one log-compressed panel per image mode, frame rate and recording status in the title. |
| `flogc` | Log compression normalised to the maximum. |

## `dependencies/utilities`

| Function | Description |
| --- | --- |
| `xw_load_rf_recording` | Loads frames from an RF recording (one file per frame, or the older single `rf_data.bin`). |
| `xw_parse_voltages` | Reads the `--sweep` voltage list. |
| `TimeTag2Sec` | Converts the two time-tag samples of a frame to seconds. |
| `evalin_if_exist`, `check_if_exist` | Read base-workspace variables with a default. |
| `fprintfd` | `fprintf` only when `DEBUG = 1` in the base workspace. |
| `save/saveDataMenu` | Save menu used by **Save Data**: choose variables, figures, compression, folder and filename. Configured through `SaveDataMenuSettings`; `saveDataMenu('apply_settings')` applies new settings to an open menu. |

## Base-workspace state

| Variable | Contents |
| --- | --- |
| `P` | Parameters (see [Parameters](parameters.md)); updated with `x_axis`, `z_axis`, ray angles. |
| `UISTATES` | GUI state: `persistence`, `dr_bmode`, `dr_xam`, `save_mode`, `record_num_frames`. |
| `BFData`, `BFData_raw` | Latest beamformed frame with and without persistence. |
| `XWRecord` | Recording state: `active`, `mode`, `num_frames`, `frame_count`, `folder`, `pending` (background writes), `time_tags`, … |
| `XWSweep` | Voltage sweep state: `active`, `voltages`, `step`, `phase`, `hv_set`, `mean_xam`, … |
| `XWBurst` | Burst state: `active`, `image_count`, `plan`, `voltage`, `images`, `folder`, … |
| `SaveDataMenuSettings` | Defaults for the save menu. |
