---
title: Testing
nav_order: 11
---

# Testing

All features can be tested with one command, without clicking anything:

```bash
tests/run_tests.sh               # unit tests + integration test in simulation
tests/run_tests.sh --hardware    # integration test on the Vantage hardware
tests/run_tests.sh --unit-only   # unit tests only (no VSX, no display)
```

The exit code is 0 when everything passed, so the script can also be used in
scripts or before committing changes. Logs are written to
`tests/output/<date_time>/` (`unit.log`, `integration.log`); data written by
the tests is deleted afterwards unless `--keep-data` is given.

| Option | Description |
| --- | --- |
| `--hardware` | Run the integration test on the hardware instead of in simulation. The transducer transmits at up to 2.5 V, so it must be in water or on a phantom. |
| `--cpu-beamformer` | Use the MATLAB beamformer. Chosen automatically if there is no compiled `MLBFXWave` for the platform. |
| `--unit-only` | Skip the integration test. |
| `--keep-data` | Keep the recordings, snapshots and sweep written by the test. |

`MATLAB=...` and `VANTAGE_ROOT=...` work as for `run_xam.sh`. The integration
test is stopped and fails after `XAM_TEST_TIMEOUT` seconds (default 1200).

## Unit tests

`tests/unit/`, run with MATLAB's `runtests`; no VSX or display needed.

| Test | Checks |
| --- | --- |
| `test_parse_voltages` | `--sweep` voltage ranges and lists; bad input is rejected and never evaluated |
| `test_rf_recording` | Background RF recording round trip (bit-exact, 4th frame not recorded, subsets); a failed write stops the recording and is listed in `failed_frames` |
| `test_beamform_cpu` | `xw_beamform_cpu` focuses a synthetic echo at the right depth and ray; multiple frames are handled |

## Integration test

`tests/integration/` runs the real `xAM_imaging.m` in VSX. A timer presses the
controls in turn, using the actual GUI buttons, sliders and switch, and checks
each result:

| Step | Checks |
| --- | --- |
| `wait_for_gui`, `start_sequence` | VSX starts; **Start Seq.** starts acquisition and frames are processed |
| `persistence` | The slider sets the persistence and `BFData` is blended |
| `dynamic_range` | **DR B-Mode** and **DR xAM** change the display colour limits |
| `save_mode` | The **Save mode** switch sets images / RF |
| `record_images`, `record_rf` | **Record** saves 3 frames of each kind; RF frames load with `xw_load_rf_recording` |
| `record_stop_early` | Pressing **Record** again stops a 20-frame recording |
| `freeze` | No frames while frozen; acquisition resumes after unfreezing |
| `save_data_images`, `save_data_rf` | **Save Data** writes a snapshot with `BFData` / `RcvData` |
| `voltage_sweep` | A short **Voltage sweep** completes, sets each voltage, saves the results and plot, and restores the voltage |
| `time_tags` (hardware only) | Hardware time tags increase from frame to frame |

The test also fails if:

- MATLAB prints an error from frame processing, a stopped recording or a
  stopped sweep;
- any dialog other than "Data saved!" appears;
- VSX closes or the test runs out of time before every step has run.

The voltage sweep in the test uses 2 and 3 V in simulation, and 1.6, 2.0 and
2.4 V on hardware.

A run in simulation takes about a minute with the CPU beamformer.
