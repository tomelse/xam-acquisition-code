---
title: Performance
nav_order: 8
---

# Performance

Everything that happens per frame (transfer, reconstruction, saving, display)
must fit in one frame period, `1 / P.fps`. Because of
`waitForProcessing = 1`, slow processing lowers the frame rate instead of
dropping frames; the time tags in a recording show the actual frame timing.

## Acquisition

With the default settings (L22-14vX, 0-10 mm, 159 rays, 1 angle):

| | |
| --- | --- |
| Transmits per frame | 477 (159 rays × 3 pulses) |
| Time between transmits | 57 µs |
| Acquisition time per frame | 27 ms |
| Maximum frame rate | 36.8 Hz |
| RF data per frame | 188 MB (732672 × 128 int16) |

At `P.fps = 2` there are 500 ms per frame for everything else.

## Measured timings

Measured on 2026-10-13 on an AMD Ryzen 9 9950X (16 cores), 121 GB RAM,
NVIDIA RTX 5070 Ti and a Samsung 990 PRO 4 TB NVMe drive, MATLAB R2024a/R2024b.
Use them as a guide; other machines will differ.

### Saving one RF frame (188 MB)

| Method | Time per frame | Throughput |
| --- | --- | --- |
| Raw `fwrite`, appended to one file (used by **Record**) | 23-33 ms | ~7 GB/s, sustained over 113 GB |
| Raw `fwrite` on a background thread | 0.6 ms blocking | limited by the drive |
| `save -v6` (uncompressed) | 53 ms | 3.5 GB/s |
| `save -v7.3 -nocompression` (used by **Save Data**) | 110 ms | 1.7 GB/s, sustained over 28 GB |
| `save -v7` / `-v7.3` (compressed) | 2.4-3.0 s | 60-80 MB/s |
| `matfile` writes into one file | 3.4 s | 55 MB/s |

Compression only shrinks RF files by about 25%, so it is not worth the time.
Opening a raw file with an explicit byte order (`fopen(..., 'ieee-le')`)
makes `fwrite` about 3.5× slower, even on little-endian machines; the recorder
uses the native byte order and stores it in `recording_info.mat`.

### Reconstruction of one frame

| Step | CPU | GPU (RTX 5070 Ti) |
| --- | --- | --- |
| Split X/L/R and subtract | 58 ms | 14 ms (including upload to the GPU) |
| Beamform 3 images (PW_L, PW_R, xAM) | ~600 ms | ~16 ms |
| Display update | ~1 ms | ~1 ms |

The GPU numbers are from a vectorised MATLAB `gpuArray` delay-and-sum
equivalent to the beamformer (results identical to the CPU version within
2e-7). A compiled CUDA beamformer should be at least as fast. On the CPU,
about 90 ms per image is spent on IQ demodulation.

### Frame-rate budget

| Configuration | Time per frame | Maximum frame rate |
| --- | --- | --- |
| CPU beamforming + raw RF recording | ~690 ms | ~1.4 Hz |
| GPU beamforming, no saving | ~75 ms | ~13 Hz |
| GPU beamforming + raw RF recording | ~100 ms | ~10 Hz |
| GPU beamforming + `-v7.3` RF saving | ~185 ms | ~5 Hz |
| GPU split and beamforming + raw RF on a background thread | ~30 ms | 20-30 Hz |

Not included: the transfer of each frame from the Vantage to the host, which
overlaps with processing of the previous frame and depends on the system.

## Practical notes

- At 30 Hz, raw RF needs ~5.6 GB/s, close to what a single fast NVMe drive
  sustains. Leave margin, or record fewer frames.
- A 500-frame RF recording is ~94 GB. Recording refuses to start if the target
  drive has less free space than needed.
- Image recordings are ~0.6 MB per frame and never limit the frame rate.
