---
title: GUI controls
nav_order: 4
---

# GUI controls

![VSX control panel](assets/img/vsx_control.png)

The controls added by this sequence are listed below. **TGC**, **TGC All
Gain**, **High Voltage P1**, **Freeze** and **Rcv Data Loop** are standard VSX
controls.

| Control | Location | Description |
| --- | --- | --- |
| **Start Seq.** | `UserB1` | Starts acquisition. The hardware is paused when VSX opens; press this once the transducer is in contact with the sample. |
| **Freeze** | VSX | Pauses and resumes the sequence. Needed before **Save Data**. |
| **High Voltage P1** | VSX | Transmit voltage. Start low and increase slowly until xAM signal appears; too high collapses the GVs. |
| **Persistence** | `UserB6` | Blends each new image with the previous one: `1.0` shows only the new frame, lower values average over more frames. Only the display and `BFData` are smoothed; recordings and `BFData_raw` are not. |
| **DR B-Mode** | `UserC6` | Dynamic range of the B-mode display [dB]. |
| **DR xAM** | `UserC5` | Dynamic range of the xAM display [dB]. |
| **Save mode** | `UserB4` | What **Save Data** and **Record** save: *xAM images* (beamformed `BFData`) or *Raw RF* (receive data). The voltage sweep has its own setting (`--sweep-save`). |
| **Save Data** | `UserC1` | Opens the save menu for a snapshot of the frozen sequence. The menu is preset for the selected save mode. |
| **Rec. frames** | `UserC3` | Number of frames saved per recording (1-500). |
| **Voltage sweep** | `UserB2` | Only with `run_xam.sh --sweep`. Starts a voltage sweep; press again to stop it. See [Voltage sweep](voltage-sweep.md). |
| **Record** | `UserC2` | While running, saves the next **Rec. frames** frames. Press again to stop early. The image window title shows `REC k/N` during a recording. |

## Image window

The image window shows one panel per beamformed image (B-mode and xAM by
default; see `P.beamform_image_modes`). Each panel is log-compressed and
normalised to its own maximum, so the xAM panel always looks bright, even when
there is little nonlinear signal. Compare saved data on a common scale to judge
the xAM level.

The title shows the frame rate, measured from the hardware time tags. In
simulation mode the time tags are zero and the frame rate shows `NaN` or
`Inf`.
