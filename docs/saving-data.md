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
20261013_151911_rf/
├── acq_parameters.mat     P, Resource, Trans, TW, TX, Receive, TPC, TGC, Media, UISTATES
├── recording_info.mat     frame count, time tags, file layout
├── frame_00001.bin        raw RF, one file per frame
├── frame_00002.bin
└── …

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
| `frame_files`, `frame_size`, `data_class`, `byte_order`, `layout` | RF recordings only: how the frame files are named and stored |
| `failed_frames` | RF recordings only: frames that could not be written (normally empty) |

`recording_info.mat` is written when the recording starts and updated when it
ends, so the frame files can still be read if a recording is interrupted.

### Raw RF file format

Each `frame_#####.bin` holds one receive frame, without a header:

- type `int16`, byte order as in `byte_order` (`ieee-le` on x86 PCs);
- `frame_size = [rows, 128]` in column-major (MATLAB) order (188 MB with the
  default settings).

Frames are written on background threads, so writing overlaps with processing
of the next frames and costs the acquisition only about 1 ms per frame. If a
frame cannot be written (for example, the disk is full), the recording stops,
the reason is printed, and the frame is listed in `failed_frames`.

Recordings made before the switch to background writing have all frames in a
single `rf_data.bin` (`rf_file` in `recording_info.mat`). `xw_load_rf_recording`
reads both formats.

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
reconstruction. Only complete frame files are read; asking for a missing or
incomplete frame gives an error that lists the frames that are available.

### Reconstructing RF data offline

`examples/reconstruct_rf.m` reconstructs a saved RF recording folder or RF
snapshot with the same code as the live view (`xw_reconstruct_setup`,
`xw_reconstruct_frame`), giving identical images, and shows the image stack:

```matlab
data_path = 'data/20261013_151911_rf';
run('examples/reconstruct_rf.m')   % leaves images, images_dB, x_mm, z_mm in the workspace
```

It is meant as a starting point for your own processing.

### Loading RF recordings in Python

```python
import numpy as np
from scipy.io import loadmat

folder = "/path/to/data/20261013_151911_rf"
info = loadmat(f"{folder}/recording_info.mat", squeeze_me=True)
rows, channels = (int(n) for n in info["frame_size"])

def load_frame(k):
    """Frame k (1-based) as (channels, rows): MATLAB [rows, channels] is column-major."""
    fn = f"{folder}/" + info["frame_files"].replace("%05i", f"{k:05d}")
    return np.fromfile(fn, dtype="<i2").reshape(channels, rows)

frame = load_frame(1)   # (channels, rows)
channel_1 = frame[0]    # (rows,)
```

Use `dtype=">i2"` if `byte_order` is `ieee-be`.

### Time tags

The hardware writes a time tag into the first two samples of channel 1 of each
frame. It is converted to seconds with `TimeTag2Sec`:

```matlab
t = TimeTag2Sec(RF(1:2, 1, k));   % frame k, in seconds
```

The same values are stored per frame in `recording_info.mat`.
