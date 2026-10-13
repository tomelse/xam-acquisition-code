---
title: Simulation mode
nav_order: 9
---

# Simulation mode

The Verasonics software can simulate acquisitions without hardware. This is
useful for testing changes to the sequence, the GUI and data saving.

## Running a simulation

In `xAM_imaging.m`, set

```matlab
Resource.Parameters.simulateMode = 1;
```

and run the script as usual (see [Quick start](quick-start.md)). The simulator
uses the point targets from `pt1` (`Media`), moved slightly between frames by
`movePoints`.

Simulation needs:

- a Verasonics licence that includes the simulator and is issued for this
  computer (see [Installation](installation.md#verasonics-licence));
- the beamformer `MLBFXWave` (currently Windows only).

## What to expect

![Simulated B-mode and xAM on a common dB scale](assets/img/sim_common_scale.png)

- **B-mode** shows the point targets of `pt1` between about 2.8 and 8.5 mm depth.
- **xAM** is empty: about 80 dB below the B-mode peak. The simulator
  is linear, so `X − L − R` cancels. This is a good check that the X, L and R
  transmits are consistent.
- In the live display the xAM panel still shows the targets, because each
  panel is normalised to its own maximum.
- **Time tags** are zero, so the frame rate in the image title shows `NaN` or
  `Inf`, and recordings report timing from the host clock.

## Testing without the beamformer

On Linux, the sequence, GUI and recording can be tested in simulation with a
MATLAB stand-in for `MLBFXWave` (a CPU delay-and-sum using the same lookup
tables, ~200 ms per image). Put it on the path ahead of
`dependencies/reconstruct`, and temporarily disable the
`exist('MLBFXWave', 'file') ~= 3` check in `xw_beamform_run`, which only
accepts a compiled beamformer. The frame rate drops to about 1-1.3 Hz, but all
controls and saving work.
