---
title: How it works
nav_order: 6
---

# How it works

## Transmit scheme

The image is built ray by ray. Each ray is centred on a *bisector* position
along the array (`P.ray_positions`), with half-pitch scanning placing bisectors
between elements as well. For each ray, three transmits are made with the
aperture centred on the bisector:

| Pulse | Aperture | Delays |
| --- | --- | --- |
| **X** | Both halves | Left half steered right, right half steered left: two plane waves that cross along the bisector |
| **L** | Left half only | Same delays as the left half of X |
| **R** | Right half only | Same delays as the right half of X |

For an integer bisector the centre element is switched off (odd aperture), so
L and R together use exactly the same elements and delays as X.

For a linear medium, the echo of X equals the sum of the echoes of L and R, so

```text
xAM = X − L − R
```

is zero. Buckling GVs respond nonlinearly to the higher pressure where the
two plane waves cross, and leave a residual signal. Because the waves only
overlap along the bisector, nonlinear *propagation* (which builds up along each
wave separately) cancels too.

The B-mode image (`PW`) is formed from `L + R`.

### Aperture and angle per ray

- In the centre of the array the aperture is `P.aperture_size_max` elements.
  Near the edges it shrinks so it fits on the array, down to
  `P.aperture_size_min`.
- The plane waves only cross down to a depth
  `aperture × pitch / 2 × cot(angle)`. With `P.use_adaptive_xwave_angle`, the
  angle is reduced for smaller apertures so every ray reaches
  `P.max_image_depth`. The dashed line in the image window shows the crossing
  depth per ray.
- Transmit apodization (`P.transmit_apodization`) is applied to each half
  aperture to reduce edge waves.

## Sequence

```text
Event 1   initialise beamformer (process frame 1)
Event 2   display initial image                       → return to MATLAB
Event 3   save acquisition parameters                 → return to MATLAB
Event 4   stop hardware (wait for Start Seq.)
Event 5…  for each of the 4 RF frames:
            for each chunk of rays (P.num_chunks = 8):
              for each ray (and angle): transmit X, L, R, receive
              transfer the chunk to host, wait for transfer
              beamform the chunk, mark transfer processed
            (the last chunk also records, applies persistence)
            display                                    → return to MATLAB
          jump back to Event 5
```

`Resource.Parameters.waitForProcessing = 1` makes the hardware wait before
transferring a new frame until the software has started processing the
previous one. Frames are therefore never overwritten before they are
processed: if processing or saving is slow, the frame rate drops instead of
frames being skipped.

### Chunks

The frame is transferred and beamformed in `P.num_chunks` groups of
consecutive rays (sub-frame DMA). While chunk *k* is beamformed on the host,
the hardware acquires the rays of chunk *k + 1*, so only the last chunk is
left to do when the frame has been acquired. This shortens the delay between
acquisition and image, and lets the frame rate approach `P.max_framerate`
when beamforming a whole frame would take longer than the idle time between
frames. The images are identical to those of a whole-frame reconstruction
(`num_chunks = 1`). Each chunk has its own process function
(`xw_beamform_chunkNN`, which calls `xw_beamform_run(RFData, k)`). Chunks need
`P.num_accumulations = 1`; otherwise `num_chunks` is set to 1.

## RF data layout

Each frame in the receive buffer (`RcvData{1}(:, :, frame)`) is an int16 array
(for `P.rf_datatype = 'half'`: the bit patterns of half data, see [Saving data](saving-data.md#half-rf-data))
of `rows × 128` channels, with

```text
rows = 3 pulses × num_rays × num_angles × Nz_RF
```

(`732672 = 3 × 159 × 1 × 1536` with the defaults, 188 MB per frame). The rows
are ordered as:

```text
[ ray 1 | ray 2 | … ]
each ray: [ X | L | R ], each with the angles in order
each acquisition: Nz_RF samples (Receive.startSample … endSample)
```

So for ray `r`, pulse `p` (0 = X, 1 = L, 2 = R) and angle `a` (1-based), the
samples are rows

```text
(((r − 1) × 3 + p) × num_angles + a − 1) × Nz_RF + (1 : Nz_RF)
```

All pulses of a ray are together so that groups of rays can be transferred
and beamformed separately (see Chunks). `P.rf_layout = 'ray-major'` marks this
order. Data recorded with earlier versions has no `rf_layout` and is
'pulse-major' (all rays of X, then all rays of L, then of R); the
reconstruction functions handle both.

Sampling: `NS200BW`, four samples per wavelength at the demodulation frequency
(62.5 MHz at 15.625 MHz for the L22-14vX). The first two samples of channel 1
of each frame hold the hardware time tag (see `TimeTag2Sec`).

## Reconstruction

`xw_beamform_run` is called once per frame (once per chunk, with `P.num_chunks > 1`):

1. Split the frame into the X, L and R blocks and compute `X − L − R` in RF.
2. On the first call, compute the delay lookup tables (`xw_beamform_compute_LUT`):
   - transmit delay per depth, ray and angle, from the crossing plane wave;
   - receive delay per depth, ray and element, limited to elements within
     the f-number aperture (`P.fNumber`, default 1.28), including the
     transmit-waveform peak and lens corrections.
3. Beamform with `xw_beamform_gpu` (GPU, IQ demodulation, linear
   interpolation; `xw_beamform_cpu` is the MATLAB reference):
   `PW = bf(L) + bf(R)` and `xAM = bf(X − L − R)`.
4. Pass the frame to the recorder (`xw_record_frame`) if a recording is active.
5. Apply persistence and store the result in `BFData` in the base workspace.

The image grid has one column per ray (`P.x_axis`) and a row every half
wavelength from `P.image_start_depth_mm` to `P.image_end_depth_mm`
(`P.z_axis`): 212 × 159 pixels with the defaults.
