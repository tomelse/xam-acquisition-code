---
title: Performance
nav_order: 9
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
| Raw `fwrite`, one file per frame, on background threads (used by **Record**) | ~1-2 ms blocking | 30 fps (5.6 GB/s) sustained over 28 GB |
| Raw `fwrite`, appended to one file, synchronous | 23-33 ms | ~7 GB/s, sustained over 113 GB |
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
| Beamform 3 images (PW_L, PW_R, xAM) | ~650 ms (`xw_beamform_cpu`) | ~26 ms (`xw_beamform_gpu`, including uploading the RF) |
| Display update | ~1 ms | ~1 ms |

`xw_beamform_gpu` (MATLAB `gpuArray`) takes about 8.6 ms per image on the RTX
5070 Ti in R2024a, about 25× faster than `xw_beamform_cpu`, and matches it to
within 1e-7 (relative). Most of its time is uploading the RF block (~62 MB per
image); computing X − L − R on the GPU from a single upload of the frame would
save part of it. A hand-written CUDA kernel was about 5 ms per image, but
needed a compiler setup that breaks on new Linux distributions, which is not
worth 3.6 ms here. On the CPU, about 90 ms per image is spent on IQ
demodulation.

### Frame-rate budget

| Configuration | Time per frame | Maximum frame rate |
| --- | --- | --- |
| CPU beamforming, with or without RF recording | ~660 ms | ~1.5 Hz |
| GPU beamforming (CPU split), with or without RF recording | ~85 ms | ~11 Hz |
| GPU split and beamforming, with or without RF recording | ~40 ms | ~25 Hz |
| For comparison: GPU beamforming + synchronous `-v7.3` RF saving | ~185 ms | ~5 Hz |

RF recording runs on background threads and adds only ~1-2 ms per frame, so
it no longer limits the frame rate. It was tested at 30 fps for 150 frames
(28 GB) with 16 ms of emulated beamforming per frame, without slowing down.

At most `P.num_rf_frames − 2` (= 2) frame writes are allowed to run on. If
the drive falls behind, processing waits for the oldest write, and the frame
rate drops rather than risking data being overwritten in the receive buffer.
Recording also warms up the background threads when **Record** is pressed
(~0.6 s the first time in a session).

Not included: the transfer of each frame from the Vantage to the host, which
overlaps with processing of the previous frame and depends on the system.

## Practical notes

- At 30 Hz, raw RF needs ~5.6 GB/s, close to what a single fast NVMe drive
  sustains. Leave margin, or record fewer frames.
- A 500-frame RF recording is ~94 GB. Recording refuses to start if the target
  drive has less free space than needed.
- Image recordings are ~0.6 MB per frame and never limit the frame rate.
