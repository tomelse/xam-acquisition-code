---
title: Installation
nav_order: 2
---

# Installation

## Requirements

| Component | Version | Notes |
| --- | --- | --- |
| Verasonics software | Vantage 4.x, or Vantage NXT 2.2 / 2.3 | NXT 2.3.2-p2 has been tested |
| MATLAB | R2021b or later for Vantage 4.x; **R2024a** for Vantage NXT 2.2 / 2.3 | NXT checks the MATLAB release when it is activated and refuses unsupported ones |
| Signal Processing Toolbox | | Transmit apodization windows (`tukeywin`, `hamming`, `kaiser`) |
| CUDA Toolkit | ≥ 12.0 (12.9.1 recommended) | Needed by the GPU beamformer `MLBFXWave` |
| Transducer | L22-14vX or L11-5v | Other 128-element linear arrays may work but are untested |

> **Warning:** the beamformer `MLBFXWave` is currently only available as a Windows binary
> (`dependencies/reconstruct/MLBFXWave.mexw64`). On Linux and macOS the sequence
> runs, but stops with *"Could not find MLBFXWave"* when it tries to beamform
> the first frame.

## Getting the code

```bash
git clone <repository url> xAM-imaging
```

The repository can live anywhere; it does not have to be inside the Verasonics
folder. All paths inside the repository are found relative to
`xAM_imaging.m`.

```text
xAM-imaging/
├── xAM_imaging.m              main setup script: edit parameters here and run it
├── dependencies/
│   ├── display/               live display (xw_plot)
│   ├── reconstruct/           beamforming (xw_beamform_run, MLBFXWave)
│   ├── sequence/              GUI callbacks, transmit setup, recording
│   └── utilities/             helpers, save menu, RF recording loader
├── MatFiles/                  generated sequence file for VSX (created on first run)
├── data/                      default location for saved data (created on demand)
└── docs/                      this documentation
```

## Verasonics licence

Both hardware and **simulation mode** need a valid Verasonics licence
(`license.enc` in the root of the Verasonics software folder). The licence is
tied to the computer it was issued for: copying a licence from another PC gives

```text
Error checking for 'Simulator' license: The host controller is not licensed.
```

To get a licence for a new computer, run `systemInfo` from the Verasonics root
folder in MATLAB and send the resulting `systemInfo.txt` to
licensing-request@verasonics.com. Generate it from a normal MATLAB session: the
report includes the environment variables of the session it was run from.

## Operating systems

- **Windows**: fully supported, including the GPU beamformer.
- **Linux**: the Verasonics software supports Ubuntu 22.04. Newer versions work
  but give a warning when the software is activated. The beamformer is not yet available.
