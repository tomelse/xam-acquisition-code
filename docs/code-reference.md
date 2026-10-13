---
title: Code reference
nav_order: 11
---

# Code reference

The sequence shares state with VSX through the MATLAB base workspace: `P`,
`UISTATES`, `BFData`, `XWRecord` and the Verasonics structs are read and
written with `evalin('base', …)` / `assignin('base', …)`.

## Main script

| File | Description |
| --- | --- |
| `xAM_imaging.m` | Sets parameters, builds the Verasonics structs (`Trans`, `TW`, `TX`, `Receive`, `TGC`, `Process`, `SeqControl`, `Event`, `UI`), saves them to `MatFiles/xAM_imaging.mat` and starts `VSX`. |

## `dependencies/sequence`: setup and GUI callbacks

| Function | Description |
| --- | --- |
| `xw_setup_build_transmit` | Builds the X, L and R `TX` structures for one ray and angle: aperture size, adaptive angle, apodization. |
| `xw_setup_compute_delays` | Transmit delays and channels for X, L and R, for integer and half-element bisectors. |
| `xw_setup_timetag` | Enables hardware time tagging (hardware only). |
| `xw_sequence_start` | **Start Seq.**: starts the hardware at the first acquisition event and unfreezes. |
| `xw_sequence_save_acquisition_parameters` | Saves the sequence structs to `<save_path>/<name>_ACQ_PARAMETERS.mat`, or to a given path. |
| `xw_change_persistence` | **Persistence** slider. |
| `xw_change_dr` | **DR B-Mode** and **DR xAM** sliders. |
| `xw_change_save_mode` | **Save mode** switch: sets `UISTATES.save_mode` to `'images'` or `'rf'`. |
| `xw_change_record_frames` | **Rec. frames** slider. |
| `xw_save_data` | **Save Data**: presets the save menu for the save mode and opens it. |
| `xw_record_start` | **Record**: checks disk space, creates the recording folder, opens the RF file and starts the recording (or stops a running one). |
| `xw_record_frame` | Called for every frame from `xw_beamform_run`; appends RF to `rf_data.bin` or saves `frame_#####.mat`. |
| `xw_record_save_info` | Writes `recording_info.mat`. |
| `xw_record_finish` | Closes the RF file, writes the final `recording_info.mat`, reports the frame rate. |

## `dependencies/reconstruct`: beamforming

| Function | Description |
| --- | --- |
| `xw_beamform_run` | External process function called per frame: splits X/L/R, forms `X − L − R`, beamforms `PW` and `xAM`, records, applies persistence, stores `BFData`. |
| `xw_beamform_compute_LUT` | Transmit and receive delay lookup tables, including the f-number mask, waveform peak and lens corrections. |
| `MLBFXWave` | GPU beamformer (compiled; `MLBFXWave.m` only holds its documentation). |

## `dependencies/display`

| Function | Description |
| --- | --- |
| `xw_plot` | Live image window: one log-compressed panel per image mode, frame rate and recording status in the title. |
| `flogc` | Log compression normalised to the maximum. |

## `dependencies/utilities`

| Function | Description |
| --- | --- |
| `xw_load_rf_recording` | Loads frames from an RF recording (`rf_data.bin`) with `memmapfile`. |
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
| `XWRecord` | Recording state: `active`, `mode`, `num_frames`, `frame_count`, `folder`, `fid`, `time_tags`, … |
| `SaveDataMenuSettings` | Defaults for the save menu. |
