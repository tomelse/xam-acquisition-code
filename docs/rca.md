---
title: Row-column array (sound sheet)
nav_order: 12
---

# xAM with a row-column array ("sound sheet")

`xAM_imaging_RCA.m` is the version of the xAM script for row-column arrays
(RCA), started with `./run_xam_rca.sh`. It supports the two Vermon probes in
`computeTrans`:

| Probe | Elements | Frequency | Pitch | Voltage limit |
|---|---|---|---|---|
| `RC15gV` (default) | 80 + 80 | 13.6 MHz | 0.11 mm | 30 V |
| `RC6gV` | 128 + 128 | 6 MHz | 0.2 mm | 40 V |

```
./run_xam_rca.sh --probe RC15gV            # or RC6gV
./run_xam_rca.sh --sim --cpu-beamformer    # simulation, no hardware or GPU
```

The other options are those of `run_xam.sh` (`--sweep`, `--save`, `--float16`,
...). The starting values of the depth and the aperture per probe are in
`dependencies/rca/xw_rca_probe.m`; they are to be tuned on the hardware.

## Transmits and receive

The transmits are those of the linear array (see [How it works](how-it-works.md)):
for every ray an xWave (X, all elements of the aperture) and its two halves
(L, R), 1 half cycle at the centre frequency. A ray is a sub-aperture of
`P.aperture_size_min` to `max` elements of one half of the array, scanned over
that half.

- **Orientation 1**: transmit with the elements of one half of the array,
  receive with *all* elements of the other half (orthogonal to the transmit
  elements). **Orientation 2**: the halves exchanged.
- Elements `1:N/2` are the "x elements" and `N/2+1:N` the "y elements" of the
  Verasonics RC examples. `P.first_orientation` selects which half transmits
  first (1: elements `1:N/2`).
- The acquisitions of a frame are ordered ray by ray, orientation 1 first.
  The receive buffer has 256 channels, also for the RC15gV (160 elements),
  as in the Verasonics RC examples; the receive elements of an orientation
  are the buffer columns `Trans.Connector(rx elements)`.

## Reconstruction and display

Every ray gives a plane: the transmit localises the ray along its aperture
(the xWave, as in the linear array), the orthogonal receive elements resolve
the other direction (delay-and-sum with the f-number of the linear array).
The rays together are a volume per orientation. The orientations are
combined incoherently (root mean square of the envelopes) into
`BFData.PW` and `BFData.xAM`, volumes `[depth, second axis, first axis]`
(`P.z_axis`, `P.axis_second`, `P.axis_first` [m]). These are real
(envelope), unlike the complex images of the linear array.

`xw_rca_plot` shows three orthogonal slices of each mode; the sliders at the
bottom of the figure move the slices. The dynamic range and persistence
sliders are those of the linear array. Record, Save Data and the voltage
sweep work as for the linear array (the sweep measures the mean xAM envelope
in the volume where the two plane waves cross).

The code is in `dependencies/rca/`; `xw_rca_beamform_cpu` is the reference
beamformer, run on the GPU by `xw_rca_beamform_gpu`.

## Burst

The **Burst** button works as for the linear array (see [Burst](burst.md)):
`P.burst_pre_frames` frames at the imaging voltage, `P.burst_collapse_frames`
at the burst voltage (TPC profile 2, `P.burst_voltage`, at most
`Trans.maxHighVoltage`: 30 V for the RC15gV, 40 V for the RC6gV), then
`P.burst_post_frames`. The burst voltage collapses gas vesicles irreversibly:
try a short burst at 1.6 V first (`XAM_BURST_FRAMES=3,4,2 XAM_BURST_VOLTAGE=1.6`).

- **Transmits**: focused (`P.burst_focus_mm`), 7 half cycles, aperture of
  `P.burst_num_tx` elements of one half of the array, all positions of the
  aperture as rays, three pulses per ray (all elements, odd elements off, even
  elements off), subtracted on the hardware (`Receive.Apod = -1`) to give the AM
  signal. The focus is in the plane of the aperture; the elements are long in
  the other direction, which gives the sheet. As in the xAM images, the rays
  are transmitted with one half of the array and received with the other, then
  the halves are exchanged.
- **Reconstruction**: the same RCA beamformer as the xAM images (volume per
  orientation, combined into one), with the transmit delay of a focused beam
  (the delay of the centre of the aperture + z/c). Unlike the linear array
  (Verasonics reconstruction during the burst), the RF of every frame is copied
  to host memory while the burst runs (`xw_rca_burst_capture`; about 20 MB per
  frame for the RC15gV, 60 MB for the RC6gV) and the volumes are reconstructed
  one after the other at the end of the burst, which can take a minute.
  There is no live preview.
- **Frame rate**: the copy of a frame takes some time, so the frame rate is
  lower than the nominal `P.burst_frame_period`. The time at which each frame
  was copied is saved in `burst.mat` (`host_time`); the voltage of each frame is
  not affected.
- **Output**: `burst.mat` has `images` [depth, second axis, first axis, frames]
  (envelope, linear), the axes in mm, the voltages, and `analysis` (frame
  `P.burst_pre_frames + 1` minus the mean of the next frames at the burst
  voltage, as volumes). `burst_analysis.png/.fig` shows it as two slices of the
  volume at the position of the largest difference; `burst.png` the mean level
  per frame.

## Status and to be verified on the hardware

- Tested so far: the unit tests (`tests/unit/test_rca_*.m`, synthetic data) and
  `tests/run_tests.sh --rca` in *simulation* on Vantage NXT 2.3.2 (all 18 steps,
  including two bursts, record, sweep and the offline reconstruction check, with
  the CPU beamformer). Not tested on hardware, with an RCA probe, with the GPU
  beamformer or in simulation with the RC6gV. In simulation the linear
  simulator is used, so it says nothing about the element mapping or the
  geometry. On hardware: `tests/run_tests.sh --rca RC15gV --hardware` or the
  MATLAB equivalent with `XAM_SCRIPT=xAM_imaging_RCA.m` and `XAM_PROBE=RC15gV`.
- Burst: the sequence waits for `xw_rca_burst_capture` after every frame
  (`waitForTransferComplete`, process, `markTransferProcessed`, as in the
  live loop). Check that the burst runs to the end, that the frames at the burst
  voltage are brighter by about the voltage ratio when `P.burst_voltage` differs
  from the imaging voltage, and that the transmit delay of the focused beam
  puts the scatterers at the right depth (a wire target).
- Which half of the array is the "row" and which the "column" in your
  set-up: check the orientation with a wire target, and use
  `P.first_orientation`.
- The mapping of the receive buffer columns to the elements
  (`Trans.Connector`) and the hardware time tag channel
  (`xw_rca_time_tag`): check with a point target that it is focused at the
  right position in both orientations.
- Simulation mode with a row-column array (`Trans.type = 4`) has not been
  verified; see [Simulation](simulation.md).
- Offline reconstruction of RCA recordings: `xw_rca_reconstruct_setup` and
  `xw_rca_reconstruct_frame` do it (as `examples/reconstruct_rf.m` does for the
  linear array); there is no example script yet.
