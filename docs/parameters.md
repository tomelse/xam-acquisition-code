---
title: Parameters
nav_order: 5
---

# Parameters

All parameters are set near the top of `xAM_imaging.m`, in the struct `P`
(and `Trans.name`). The script is re-run to apply changes.

## Basic

| Parameter | Default | Description |
| --- | --- | --- |
| `Trans.name` | `'L22-14vX'` | Transducer. Tested: `L22-14vX`, `L11-5v`. |
| `P.image_start_depth_mm` | `0` | Start depth of the image [mm]. |
| `P.image_end_depth_mm` | `10` | End depth of the image [mm]. |
| `P.xwave_angles` | `17` | xWave angle [degrees]. Check that the plane waves still cross at the maximum depth (a warning is shown if not). |
| `P.speed_of_sound` | `1480` | Speed of sound [m/s]: 1480 for water/agar, 1540 for tissue. |
| `P.image_voltage` | `2.5` | Initial transmit voltage [V]. Keep low to avoid GV collapse. |
| `P.aperture_size_min` | `48` | Minimum number of elements in the transmit aperture. Sets how close to the array edges rays are placed (48 gives a wide field of view). |
| `P.aperture_size_max` | `64` | Maximum number of elements in the transmit aperture. |
| `P.transmit_apodization` | `'tukey'` | Transmit apodization against edge waves: `'none'`, `'tukey'`, `'hamming'` or `'kaiser'`. |
| `P.fps` | `2` | Frame rate [Hz]. An error is raised if it exceeds the maximum the sequence allows. |
| `P.save_path` | `<repo>/data` | Default folder for **Save Data** snapshots. |
| `P.record_path` | `P.save_path` | Folder for **Record** recordings. Raw RF is ~190 MB per frame, so use a fast drive. |
| `P.record_num_frames` | `20` | Initial value of the **Rec. frames** slider. |

## Voltage sweep

See [Voltage sweep](voltage-sweep.md). The voltages and frames per voltage are
normally set with `run_xam.sh --sweep` and `--sweep-frames`.

| Parameter | Default | Description |
| --- | --- | --- |
| `P.sweep_voltages` | from `--sweep` | Voltages to sweep [V]. Empty: no sweep, no **Voltage sweep** button. |
| `P.sweep_passes` | `2` | Passes through the voltages. |
| `P.sweep_frames` | `5` (or `--sweep-frames`) | Frames recorded and measured per voltage. |
| `P.sweep_save_mode` | `'images'` (or `--sweep-save`) | Saved per voltage: `'images'` (~0.6 MB per frame) or `'rf'` (~190 MB per frame). |
| `P.sweep_settle_frames` | `2` | Frames discarded after each voltage change. |
| `P.sweep_settle_s` | `1` | Minimum settle time after a voltage increase [s]. |
| `P.sweep_settle_s_down` | `3` | Minimum settle time after a voltage decrease [s]. |
| `P.sweep_max_voltage` | `25` | Highest voltage a sweep may use [V]. The L22-14vX limit is 30 V. |

## Advanced

| Parameter | Default | Description |
| --- | --- | --- |
| `P.num_accumulations` | `1` | Number of RF acquisitions summed on the hardware per transmit. Increases SNR but lowers the maximum frame rate, and can clip the signal. |
| `P.rf_datatype` | `'int16'` | Format of the acquired RF data: `'int16'`, or `'half'` (16 bit floating point, `Receive.datatype`). Half has more dynamic range for weak signals and allows accumulating up to 512 acquisitions without overflow, but less precision for large echoes. The reconstruction multiplies half data by 256 (the system divides the 22 bit filter output by 256 before storing it as half), so images have the same scale as with int16. The data is still stored as `int16` bit patterns; see [Saving data](saving-data.md#half-rf-data). |
| `P.num_chunks` | `8` | The frame is transferred and beamformed in this many groups of rays while the next rays are acquired (1 = whole frame at the end). Images are identical. Needs `num_accumulations = 1`. See [How it works](how-it-works.md). |
| `P.use_adaptive_xwave_angle` | `true` | Lowers the xWave angle for rays near the array edges (smaller apertures), so the plane waves still cross down to the maximum depth. |
| `P.use_half_pitch_scanning` | `true` | Places rays every half element instead of every element: twice the lateral sampling, half the maximum frame rate. |
| `P.transmit_frequency` | `Trans.frequency` | Transmit frequency [MHz]. |
| `P.beamform_image_modes` | `{'PW', 'xAM'}` | Images to reconstruct and display: `'PW'` (B-mode from L + R), `'xBmode'` (B-mode from X), `'xAM'`. |
| `P.timetag_enabled` | `1` | Enables the hardware time tags used for the frame rate display and recording timing. |
| `P.num_rf_frames` | `4` | Number of frames in the receive buffer. Must be at least 4. |
| `P.use_cpu_beamformer` | `false` (`true` with `--cpu-beamformer`) | Use the slow MATLAB beamformer `xw_beamform_cpu` instead of the GPU beamformer. |
| `P.fNumber` | `1.28` | Receive f-number used in beamforming (optional, set in `P` to override). |

## Fixed and derived values

These are computed by the script; change them only if you know what you are
doing.

| Value | Description |
| --- | --- |
| `P.num_pulses = 3` | Pulses per ray: X (full aperture), L (left half), R (right half). |
| `P.ray_positions` | Ray positions in element indices, from `ceil(aperture_size_min/2)+1` to `128-floor(aperture_size_min/2)`, in steps of 1 or 0.5. With the defaults: 159 rays from -3.95 to 3.95 mm. |
| `P.max_image_depth` | Depth where the plane waves from the maximum aperture stop crossing: `aperture_size_max * pitch / 2 * cot(angle)`. 10.47 mm with the defaults. |
| `P.ray_angle` | Actual xWave angle per ray (adaptive angles: 12.9° at the edges to 17° in the centre with the defaults). |
| `P.Nz_RF` | Samples per acquisition and channel (1536 with the defaults). |
| `P.ttna` | Time between transmits [µs] (57 µs with the defaults). |
| `P.max_framerate` | Maximum frame rate allowed by the transmit timing (36.8 Hz with the defaults). |
| `P.x_axis`, `P.z_axis` | Image grid [m]: one column per ray, rows every half wavelength. Set by the beamformer. |
