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
| Parallel Computing Toolbox | | GPU beamformer (`gpuArray`). Without it, use the slow CPU beamformer (`--cpu-beamformer`) |
| NVIDIA GPU and driver | | GPU beamformer. No CUDA toolkit or compiler is needed |
| Transducer | L22-14vX or L11-5v | Other 128-element linear arrays may work but are untested |

## Beamformer

Images are reconstructed on the GPU by `xw_beamform_gpu`, written in MATLAB with
`gpuArray` (Parallel Computing Toolbox): there is nothing to compile, and it runs
on any platform with an NVIDIA GPU. The script uses, in this order:

1. a compiled `MLBFXWave` on the MATLAB path, if you have one (same interface,
   described in `dependencies/reconstruct/MLBFXWave.m`);
2. `xw_beamform_gpu`;
3. with `run_xam.sh --cpu-beamformer` (or `P.use_cpu_beamformer = true`), the
   slow reference `xw_beamform_cpu`, which needs no GPU or toolbox.

If the GPU is newer than the MATLAB release (for example an RTX 50-series GPU
with R2024a), the script enables MATLAB's CUDA forward compatibility itself.
MATLAB then compiles its GPU libraries for the GPU the first time it is used,
which takes from about 30 s to several minutes, once. `run_xam.sh` sets
`CUDA_CACHE_MAXSIZE` so the result is kept between sessions; when starting
MATLAB another way, set it yourself (`export CUDA_CACHE_MAXSIZE=4294967296`)
to avoid repeating the compilation.

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
│   ├── reconstruct/           beamforming (xw_beamform_run, xw_beamform_gpu, xw_beamform_cpu)
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
