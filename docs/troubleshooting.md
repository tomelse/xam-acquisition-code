---
title: Troubleshooting
nav_order: 11
---

# Troubleshooting

## Starting the sequence

**`The current working directory must be the root of the Vantage NXT Software Project Folder.`**
: VSX and `activate` only run from the Verasonics root folder. The script
  changes to the folder of the activated software (where `which VSX` points),
  so check that the right Verasonics version was activated in this MATLAB
  session.

**`Verasonics software not found: run activate …`**
: The Verasonics software has not been activated in this MATLAB session. Run
  `activate` from its root folder, or start with `./run_xam.sh` (set
  `VANTAGE_ROOT=...` if it is not in `~/Documents/Code/VantageNXT-2.3.2-p2`).

**`Undefined function 'computeTrans'`**
: The Verasonics software is not activated in this MATLAB session. Run
  `activate` from the Verasonics root folder first.

**`The MATLAB version R20xxx is not supported.`**
: Each Verasonics release supports specific MATLAB releases. Vantage NXT 2.2 and
  2.3 need R2024a.

**`This version of the Linux OS is not supported by Verasonics.`**
: A warning only. The software supports Ubuntu 22.04, but runs on newer
  versions.

**A licence agreement window pops up**
: `activate` can show the Verasonics licence agreement, for example the
  first time it runs with a MATLAB installation. It waits until the agreement is
  accepted, which also blocks scripts started with `matlab -batch`.

## Licence errors

**`Error checking for 'Simulator' license: The license has expired.`**
: The licence in `license.enc` has expired. Request a renewal from
  licensing-request@verasonics.com.

**`Error checking for 'Simulator' license: The host controller is not licensed.`**
: The licence was issued for a different computer. Run `systemInfo` on this
  computer and request a licence for it (see
  [Installation](installation.md#verasonics-licence)). Check the file you
  install is really new: two downloads with the same checksum (`md5sum
  license.enc`) are the same licence.

## Beamforming

**`Could not find MLBFXWave, which is the C++ beamformer.`**
: The compiled beamformer is missing for this platform. Only a Windows build
  (`MLBFXWave.mexw64`) is available at the moment. To run without it, use the
  slow MATLAB stand-in: `./run_xam.sh --cpu-beamformer`.

**GPU code in MATLAB is very slow the first time, or `gpuDevice` seems to hang**
: MATLAB releases older than the GPU (e.g. R2024b with an RTX 50-series card)
  recompile their GPU libraries on first use, which can take 10 minutes or
  more. Set the environment variable `CUDA_CACHE_MAXSIZE=4294967296` before
  starting MATLAB so the result is cached (about 1 GB), and enable
  `parallel.gpu.enableCUDAForwardCompatibility(true)`.

## Display

**The xAM image looks bright even without GVs**
: Each panel is normalised to its own maximum. Compare the saved `BFData.xAM`
  and `BFData.PW` on a common dB scale.

**Frame rate shows `NaN` or `Inf`**
: The hardware time tags are zero, which is normal in simulation mode. On
  hardware, check `P.timetag_enabled = 1`.

## Saving

**Saving RF is slow**
: Make sure compression is off (it is by default in RF mode) and the target is
  a fast local drive. See [Performance](performance.md).

**`Recording stopped after … frames: Only … samples written to … (disk full?)`**
: The drive ran out of space during a recording. The frames written so far
  can still be loaded with `xw_load_rf_recording`; the failed frame is listed
  in `failed_frames` in `recording_info.mat`.

**`Please freeze VSX`**
: **Save Data** saves a snapshot of the frozen sequence. Press **Freeze** first,
  or use **Record** to save while running.

## MATLAB crashes at start-up

**`MATLAB is exiting because of fatal error`, crash report mentioning `libmwddux`**
: An intermittent crash in MATLAB's usage-data reporting, seen with R2024a on
  Ubuntu 26.04. It is unrelated to this code; start MATLAB again.
