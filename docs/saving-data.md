---
title: Saving data
nav_order: 7
---

# Saving data

There are two ways to save data, and both follow the **Save mode** switch
(*xAM images* or *Raw RF*):

| | **Save Data** (snapshot) | **Record** (recording) |
| --- | --- | --- |
| When | Sequence frozen | Sequence running |
| What | The current frame, or the whole receive buffer for RF | The next *N* frames (**Rec. frames**) |
| Where | Folder and filename chosen in the save menu (default `P.save_path`) | New folder in `P.record_path` |
| Format | One `-v7.3` `.mat` file | Images: `-v7.3` per frame. RF: one raw binary file |

## Snapshots (Save Data)

1. Press **Freeze**.
2. Press **Save Data**. The save menu opens, preset for the current save mode.
3. Adjust folder, filename and options if needed, and press **Save**.

| Save mode | Variables saved |
| --- | --- |
| xAM images | `BFData`, `BFData_raw`, `UISTATES`, Verasonics structs (`Trans`, `TX`, `Receive`, …), `P`; figure as `.fig` and `.png` |
| Raw RF | `RcvData` (all 4 frames of the receive buffer), `UISTATES`, Verasonics structs, `P`; figure as `.png`; no compression |

`BFData` has persistence applied, `BFData_raw` does not. Both contain:

| Field | Description |
| --- | --- |
| `PW` | B-mode image, complex IQ, `numel(P.z_axis) × numel(P.x_axis)` |
| `xAM` | xAM image, complex IQ, same size |
| `TimeTag` | Hardware time tag of the frame [s] |

Use `20*log10(abs(BFData.xAM))` for a log image; the axes are `P.x_axis` and
`P.z_axis` (in metres).

## Recordings (Record)

1. Set **Save mode** and **Rec. frames**.
2. With the sequence running, press **Record**. The image title shows
   `REC k/N`. Press **Record** again to stop early.
3. When done, the command window prints the achieved frame rate and how many
   frame intervals were longer than 1.5× the nominal interval.

Recording refuses to start if the sequence is frozen or if the disk does not
have enough free space.

Each recording gets its own folder, `P.record_path/<yyyymmdd_HHMMSS>_<mode>/`:

```text
20261013_145543_rf/
├── acq_parameters.mat     P, Resource, Trans, TW, TX, Receive, TPC, TGC, Media, UISTATES
├── recording_info.mat     frame count, time tags, file layout
└── rf_data.bin            raw RF, frames appended

20261013_145546_images/
├── acq_parameters.mat
├── recording_info.mat
├── frame_00001.mat        BFData (no persistence), TimeTag, frame_index
├── frame_00002.mat
└── …
```

### recording_info.mat

| Field | Description |
| --- | --- |
| `mode` | `'rf'` or `'images'` |
| `num_frames`, `num_frames_requested` | Frames saved, and frames asked for |
| `time_tags` | Hardware time tag per frame [s] (zero in simulation) |
| `host_times` | Host clock when each frame was saved [POSIX seconds] |
| `fps_nominal` | `P.fps` |
| `rf_file`, `frame_size`, `data_class`, `byte_order`, `layout` | RF recordings only: how `rf_data.bin` is stored |

`recording_info.mat` is written when the recording starts and updated when it
ends, so the RF file can still be read if a recording is interrupted.

### Raw RF file format

`rf_data.bin` contains the receive frames back to back, without a header:

- type `int16`, byte order as in `byte_order` (`ieee-le` on x86 PCs);
- each frame is `frame_size = [rows, 128]` in column-major (MATLAB) order;
- the whole file is `[rows, 128, frames]`.

The row layout within a frame is described in
[How it works](how-it-works.md#rf-data-layout).

### Loading RF recordings in MATLAB

```matlab
addpath(genpath('/path/to/xAM-imaging/dependencies'))
folder = '/path/to/data/20261013_145543_rf';

[RF, info] = xw_load_rf_recording(folder);          % all frames
RF5 = xw_load_rf_recording(folder, 5);              % one frame
acq = load(fullfile(folder, 'acq_parameters.mat')); % P, Receive, Trans, ...
```

`RF` is `int16 [rows × 128 × frames]`, the same layout as `RcvData{1}`, so a
frame can be passed directly to `xw_beamform_run` for offline
reconstruction. The loader uses `memmapfile`, so loading single frames from
large recordings is fast, and only complete frames are read.

### Loading RF recordings in Python

```python
import numpy as np
from scipy.io import loadmat

folder = "/path/to/data/20261013_145543_rf"
info = loadmat(f"{folder}/recording_info.mat", squeeze_me=True)
rows, channels = (int(n) for n in info["frame_size"])

# MATLAB [rows, channels, frames] (column-major) == numpy (frames, channels, rows)
rf = np.memmap(f"{folder}/rf_data.bin", dtype="<i2", mode="r")
rf = rf[: rf.size // (rows * channels) * rows * channels].reshape(-1, channels, rows)

frame = rf[0]           # (channels, rows)
channel_1 = rf[0, 0]    # (rows,)
```

Use `dtype=">i2"` if `byte_order` is `ieee-be`.

### Time tags

The hardware writes a time tag into the first two samples of channel 1 of each
frame. It is converted to seconds with `TimeTag2Sec`:

```matlab
t = TimeTag2Sec(RF(1:2, 1, k));   % frame k, in seconds
```

The same values are stored per frame in `recording_info.mat`.
