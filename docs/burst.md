---
title: Burst
nav_order: 8.5
---

# Burst

The **Burst** button acquires one burst sequence: a series of frames in which
the transmit voltage is raised to a collapse voltage and lowered again, to
collapse the gas vesicles (GVs) and follow the signal while they do. It follows
the `BURST_L22_14v_VSRyLnAM_SyncBurst` script: focused transmits (not
xWaves), a much higher frame rate than live imaging, and the images are
reconstructed and saved all at once at the end of the burst.

A burst consists of

| Frames | Voltage | Parameter |
| --- | --- | --- |
| before the collapse | imaging voltage (`High Voltage P1`) | `P.burst_pre_frames` (10) |
| collapse | burst voltage (`High Voltage P2`) | `P.burst_collapse_frames` (46) |
| after the collapse | imaging voltage | `P.burst_post_frames` (0) |

The burst voltage starts at `P.burst_voltage` (25 V) and can be changed with
the **High Voltage P2** slider before pressing **Burst**, like **High Voltage
P1** for the imaging voltage. The voltage is switched by the sequence itself
between two frames (`setTPCProfile` in a transmit without active elements,
with `P.burst_settle_us` for the transition), so each frame is acquired at a
known voltage.

## Transmit and timing

As in the script: a 40-element aperture (`P.burst_num_tx`) scanned over all 89
positions (rays), focused at 6 mm (`P.burst_focus_mm`), image depth 2 to 14 mm,
a 3.5 cycle transmit pulse (`P.burst_tw_half_cycles = 7`). Every ray is
transmitted three times: with all elements of the aperture, with only the even
ones and with only the odd ones. The echoes are accumulated on the hardware
with the last two subtracted (Receive `Apod = -1`), which gives the amplitude
modulation (AM) signal. The ray centres are the real centres of the apertures
(the script places them half an element off).

The time between acquisitions is `3 * depth / c * 2` (57 µs), and the time
between frames 10 times that (`P.burst_frame_delay_factor`): about 65 frames per
second, against at most 36 for live xAM. The actual rate depends on the DMA
transfer of the frames. All frames of the burst are kept in a receive buffer of
their own (about 40 MB per frame).

## Using it

1. Start the sequence (**Start Seq.**) with the imaging voltage you want, and
   set **High Voltage P2** to the collapse voltage.
2. Press **Burst** and confirm. The burst voltage collapses GVs irreversibly:
   the confirmation can be switched off with `P.burst_confirm = false`.
3. While the burst runs, every `P.burst_preview_every`-th frame (4) is shown in
   a **Burst preview** window. After the last acquisition all frames are
   reconstructed (Verasonics reconstruction, one image line per ray) and saved,
   and live imaging resumes at the imaging voltage.

Each burst is saved in its own folder `P.record_path/<date>_<time>_burst/`:

| File | Content |
| --- | --- |
| `burst.mat` | `images`: reconstructed intensity `[depth, lateral, frames]`; `x_axis`, `z_axis` [mm]; `voltage` [V] and `tpc_profile` (1 = imaging, 2 = burst) per frame; nominal `time` and `frame_period`; frame counts; `status`. |
| `burst.png` | Mean image level per frame, with the collapse frames shaded. |
| `acq_parameters.mat` | The sequence parameters, as for a recording. |

The raw RF is not saved. The images are not log compressed.

## Preview and frame rate

`Resource.Parameters.waitForProcessing = 1`, which the live acquisition needs,
makes the hardware wait before each transfer until the software has asked for
the latest frame, and it cannot be changed while the sequence runs. During the
burst this request is a fast reconstruction of one ray of the latest frame after
every frame. The preview is a reconstruction of all rays: the acquisition waits
for it, so the frame rate dips at every preview. Set `P.burst_preview_every = 0`
for no preview and the fastest burst. The frames are saved from the end-of-burst
reconstruction, so a preview never affects the data, only the timing.

## When the button is disabled

**Burst** is grey while it cannot be used, so that the voltage and the data
saving are not disturbed:

- during a **Record** (also while RF files of the recording are still being
  written), a **Voltage sweep**, or another burst;
- while the sequence is frozen or not started yet. VSX does not report the
  **Freeze** button, so the button is enabled again with the next frame; a
  press while frozen shows a message.

**Record** and **Voltage sweep** refuse to start during a burst. Pressing
**Start Seq.** during a burst abandons it (the images reconstructed so far are
saved with status `aborted`). **Freeze** pauses a burst, which continues when
unfrozen.

## Sequence size

The burst events are part of the sequence: a burst of 56 frames adds about
15000 acquisition events and a receive buffer of about 2 GB. Shorten the burst
with the `P.burst_*_frames` parameters if the sequence takes too long to load.
