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

## Status and to be verified on the hardware

- The BURST button is not in the RCA script yet.
- Which half of the array is the "row" and which the "column" in your
  set-up: check the orientation with a wire target, and use
  `P.first_orientation`.
- The mapping of the receive buffer columns to the elements
  (`Trans.Connector`) and the hardware time tag channel
  (`xw_rca_time_tag`): check with a point target that it is focused at the
  right position in both orientations.
- Simulation mode with a row-column array (`Trans.type = 4`) has not been
  verified; see [Simulation](simulation.md).
