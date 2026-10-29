---
title: Testing
nav_order: 11
---

# Testing

All features can be tested with one command, without clicking anything:

```bash
tests/run_tests.sh               # unit tests + integration test in simulation
tests/run_tests.sh --hardware    # integration test on the Vantage hardware
tests/run_tests.sh --unit-only   # unit tests only (no VSX, no display)
```

The exit code is 0 when everything passed, so the script can also be used in
scripts or before committing changes. Logs are written to
`tests/output/<date_time>/` (`unit.log`, `integration.log`); data written by
the tests is deleted afterwards unless `--keep-data` is given.

| Option | Description |
| --- | --- |
| `--hardware` | Run the integration test on the hardware instead of in simulation. The transducer transmits at up to 2.5 V, so it must be in water or on a phantom. |
| `--cpu-beamformer` | Use the MATLAB beamformer. Chosen automatically if there is no NVIDIA GPU. |
| `--unit-only` | Skip the integration test. |
| `--half` | Acquire the RF data as half (16 bit float) instead of int16 (`P.rf_datatype`). |
| `--fps N` | Frame rate [Hz] instead of `P.fps`. For `--hardware`, to test close to `P.max_framerate`. |
| `--keep-data` | Keep the recordings, snapshots and sweep written by the test. |

`MATLAB=...` and `VANTAGE_ROOT=...` work as for `run_xam.sh`. The integration
test is stopped and fails after `XAM_TEST_TIMEOUT` seconds (default 1200).

## Unit tests

`tests/unit/`, run with MATLAB's `runtests`; no VSX or display needed.

| Test | Checks |
| --- | --- |
| `test_parse_voltages` | `--sweep` voltage ranges and lists; bad input is rejected and never evaluated |
| `test_rf_recording` | Background RF recording round trip (bit-exact, 4th frame not recorded, subsets); a failed write stops the recording and is listed in `failed_frames` |
| `test_beamform_cpu` | `xw_beamform_cpu` focuses a synthetic echo at the right depth and ray; multiple frames are handled |
| `test_chunk_timing` | `xw_chunk_timing` (used by the hardware test) finds the spacing of acquisitions and the pauses between chunks in synthetic time tags |
| `test_reconstruct_chunks` | Reconstructing in chunks gives the same image as the whole frame, the ray-major and pulse-major layouts give the same image, half data gives the same image as the equivalent int16 data (the time tag samples are ignored), and `xw_half2single` decodes half values (and agrees with `convertHalfRcvData` if the Vantage software is on the path) |
| `test_burst_plan` | `xw_burst_plan` gives the voltage profile of each burst frame and where the sequence switches it (also for bursts that start at the burst voltage); invalid frame counts are rejected |
| `test_beamform_gpu` | `xw_beamform_gpu` matches `xw_beamform_cpu` (2 angles, 2 frames, masked elements) and picks up changed LUTs. Skipped without a usable GPU |

## Integration test

`tests/integration/` runs the real `xAM_imaging.m` in VSX. A timer presses the
controls in turn, using the actual GUI buttons, sliders and switch, and checks
each result:

| Step | Checks |
| --- | --- |
| `wait_for_gui`, `start_sequence` | VSX starts; **Start Seq.** starts acquisition and frames are processed |
| `persistence` | The slider sets the persistence and `BFData` is blended |
| `dynamic_range` | **DR B-Mode** and **DR xAM** change the display colour limits |
| `save_mode` | The **Save mode** switch sets images / RF |
| `record_images`, `record_rf` | **Record** saves 3 frames of each kind; RF frames load with `xw_load_rf_recording` |
| `record_images_again`, `record_rf_again` | A second recording in the same session (images, RF) goes to a new folder with 3 new frames, different from the first recording |
| `record_stop_early` | Pressing **Record** again stops a 20-frame recording |
| `burst` | **Burst** is disabled during a recording (checked in `record_stop_early`) and during the burst, and enabled afterwards. A short burst (3 + 4 + 2 frames, `XAM_BURST_FRAMES`) is saved with the right frame count and TPC profiles, the burst analysis figure is made, the sequence returns to live imaging. On the hardware the burst voltage is 1.6 V, below the imaging voltage: the image level must scale with the voltage, which checks that the profile is switched |
| `burst_again` | A second burst in the same session goes to a new folder, is complete, has different images, and leaves the first burst's files intact |
| `freeze` | No frames while frozen; acquisition resumes after unfreezing |
| `save_data_images`, `save_data_rf` | **Save Data** writes a snapshot with `BFData` / `RcvData` |
| `offline_reconstruction` | Offline reconstruction (whole frame) of the RF snapshot reproduces the live image, which is assembled from chunks, exactly, and `examples/reconstruct_rf.m` reconstructs the RF recording |
| `voltage_sweep` | A short **Voltage sweep** completes, sets each voltage, saves the results and plot, and restores the voltage |
| `time_tags` (hardware only) | Hardware time tags increase from frame to frame |
| `chunk_timing` (hardware only) | Time tags of the acquisitions in the RF snapshot: acquisitions within a chunk are `ttna` apart. Reports the extra pause at each chunk boundary and the time to acquire a frame (`xw_chunk_timing`) |
| `frame_rate` (hardware only) | The frame rate from the time tags of 20 frames is within 5% of `P.fps` |

The test also fails if:

- MATLAB prints an error from frame processing, a stopped recording or a
  stopped sweep;
- any dialog other than "Data saved!" appears;
- VSX closes or the test runs out of time before every step has run.

The voltage sweep in the test uses 2 and 3 V in simulation, and 1.6, 2.0 and
2.4 V on hardware.

A run in simulation takes about a minute with the CPU beamformer.

## Still to be checked on the hardware

The sequence transfers and beamforms the frame in chunks of rays
(`P.num_chunks`, see [How it works](how-it-works.md#chunks)). This was only
tested in simulation, where the images match those of the whole-frame
reconstruction exactly, but the timing and the transfers cannot be tested
there. Run the integration test on the hardware (transducer in water or on a
phantom):

```bash
tests/run_tests.sh --hardware             # all steps, at P.fps
tests/run_tests.sh --hardware --fps 30    # also close to P.max_framerate (36.8 Hz with the defaults)
```

| Open question | Checked by | What to look for |
| --- | --- | --- |
| Is every chunk complete when it is beamformed (sub-frame DMA, `srcframenum = -1`)? | `offline_reconstruction` | The live image, assembled from chunks, equals the offline whole-frame reconstruction of the snapshot (difference 0). On the hardware the data is noisy, so a chunk beamformed too early would show as a difference |
| Does the hardware keep to `ttna` when it transfers chunks, and how long is the pause at each chunk boundary? | `chunk_timing` | `within a chunk … apart` equals `ttna`; the extra pause per boundary is small compared with the time to acquire a chunk. The pause is caused by `waitForProcessing = 1` |
| Is the requested frame rate reached, also close to the maximum? | `frame_rate` (use `--fps`) | Achieved rate within 5% of the requested one. If it is lower, compare with `num_chunks = 1` (edit `P.num_chunks`) to see whether chunks help |
| Does the DMA keep up, without receive buffer overflows or timeouts? | any step | No MATLAB errors or dialogs (also checked by the test) |
| Does half data have the same scale as int16 after multiplying by 256 (`xw_reconstruct_rays`)? The manual says the system divides the 22 bit filter output by 256 for half; it does not say how int16 relates to it | not automatic: two runs, see below | Peak PW amplitude of the same target within a few percent between the formats. If the ratio is not 1, the factor 256 needs changing |
| Does half data work with `num_accumulations > 1` (up to 512 accumulations without overflow), and is the xAM noise floor lower than with int16? | not automatic | Run with `P.rf_datatype = 'half'` and `P.num_accumulations` > 1; no clipping, images as expected |
| Does the voltage switch between frames of the burst (`setTPCProfile` after a transmit without active elements, `P.burst_settle_us`)? Does the hardware complete the long burst block (56 frames, ~15000 events) and return to live imaging? | `burst` (short burst at 1.6 V); then a full burst at the real voltage | B-mode level scales with voltage in `burst.png` / `burst.mat`; no `timeToNextAcq` warnings in the MATLAB output (if there are, increase `P.burst_settle_us`); the time tags in `burst.mat` give the frame rate of the burst |
| Does every chunk call copy the whole receive buffer (~190 MB), which would cancel the gain? | not automatic | Time `xw_beamform_run` per chunk with `tic`/`toc` or the MATLAB profiler; with 8 chunks the time per chunk should be about 1/8 of the whole-frame time |

To compare the scale of half and int16 data, acquire the same static target
with both and compare the snapshots (`--keep-data` keeps them in
`tests/output/<date_time>/data/snapshots/`):

```bash
tests/run_tests.sh --hardware --keep-data           # int16
tests/run_tests.sh --hardware --keep-data --half    # half
```

```matlab
addpath(genpath('dependencies'))
for f = {'int16_run/.../snapshot_rf.mat', 'half_run/.../snapshot_rf.mat'}   % the two snapshots
    S = load(f{1}, 'P', 'Receive', 'Trans', 'TW', 'RcvData');
    R = xw_reconstruct_setup(S.P, S.Receive, S.Trans, S.TW);
    B = xw_reconstruct_frame(R, S.RcvData{1}(:, :, 1));
    fprintf('%s: peak |PW| %.3g, median |xAM| %.3g\n', S.Receive(1).datatype, max(abs(B.PW(:))), median(abs(B.xAM(:))));
end
```

In simulation the peaks agree within the variation between frames (ratio 0.99 to
1.06), and the median xAM level of half data is much lower.

To look at the acquisition timing of any RF snapshot yourself:

```matlab
S = load('snapshot_rf.mat', 'P', 'RcvData');
C = xw_chunk_timing(S.P, S.RcvData{1})   % within_chunk, pause per chunk boundary, span
```

Hardware time tags are 0 in simulation, so `chunk_timing` and `frame_rate`
only run with `--hardware`.
