#!/usr/bin/env bash
# Run all xAM imaging tests without user interaction.
#
# Usage: tests/run_tests.sh [options]
#
#   (no options)       unit tests + integration test in simulation mode
#   --hardware         run the integration test on the Vantage hardware instead.
#                      The transducer transmits (at most 2.5 V): it must be in
#                      water or on a phantom.
#   --cpu-beamformer   use the CPU beamformer (automatic if there is no NVIDIA GPU)
#   --unit-only        only the unit tests (no VSX, no display needed)
#   --half             acquire RF data as half (16 bit float) instead of int16
#   --fps N            frame rate [Hz] instead of P.fps (for --hardware, e.g. close to P.max_framerate)
#   --keep-data        keep the data written by the tests (logs are always kept)
#   -h, --help         show this help
#
# Results and logs go to tests/output/<date_time>/. Exit code 0 = all passed.
# Override MATLAB=... and VANTAGE_ROOT=... as for run_xam.sh. The integration
# test is stopped (and fails) after XAM_TEST_TIMEOUT seconds (default 1200).
set -uo pipefail

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

HARDWARE=0; UNIT_ONLY=0; KEEP_DATA=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hardware)       HARDWARE=1 ;;
        --cpu-beamformer) export XAM_CPU_BEAMFORMER=1 ;;
        --unit-only)      UNIT_ONLY=1 ;;
        --fps)            [[ $# -ge 2 ]] || { echo '--fps needs a value' >&2; exit 2; }; export XAM_FPS="$2"; shift ;;
        --half)           export XAM_RF_DATATYPE=half ;;
        --keep-data)      KEEP_DATA=1 ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$TESTS")"
MATLAB="${MATLAB:-$HOME/MATLAB2024a/bin/matlab}"
VANTAGE_ROOT="${VANTAGE_ROOT:-$HOME/Documents/Code/VantageNXT-2.3.2-p2}"
OUT="$TESTS/output/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

[[ -x "$MATLAB" ]] || { echo "MATLAB not found: $MATLAB (set MATLAB=...)" >&2; exit 2; }

# MATLAB R2024a occasionally crashes at start-up on newer Linux versions
# (usage-data reporting, unrelated to this code): retry those.
run_matlab() { # log, time limit [s], matlab args...
    local log="$1" limit="$2"; shift 2
    local rc
    for attempt in 1 2 3; do
        timeout --kill-after=30 "$limit" "$MATLAB" "$@" > "$log" 2>&1; rc=$?
        if [[ $rc -eq 124 || $rc -eq 137 ]]; then echo "   FAIL  MATLAB did not finish within $limit s (stopped)" | tee -a "$log"; return $rc; fi
        grep -q "MATLAB is exiting because of fatal error" "$log" || return $rc
        echo "  (MATLAB crashed at start-up, retrying)"
    done
    return $rc
}

FAILED=0
export CUDA_CACHE_MAXSIZE="${CUDA_CACHE_MAXSIZE:-4294967296}" # keep compiled GPU libraries (see run_xam.sh)

# ---------------------------------------------------------------- unit tests
echo "== Unit tests"
run_matlab "$OUT/unit.log" 600 -batch "addpath(genpath('$REPO/dependencies')); r = runtests('$TESTS/unit'); disp(table(r)); exit(double(~all([r.Passed])))"
if [[ $? -eq 0 ]]; then
    echo "   PASS  $(grep -c "true " "$OUT/unit.log") tests"
else
    echo "   FAIL  see $OUT/unit.log"; grep -E "Failure|Error|false" "$OUT/unit.log" | head -20
    FAILED=1
fi

# --------------------------------------------------------- integration test
if [[ $UNIT_ONLY -eq 0 ]]; then
    [[ -f "$VANTAGE_ROOT/VSX.m" ]] || { echo "Vantage software not found: $VANTAGE_ROOT (set VANTAGE_ROOT=...)" >&2; exit 2; }
    [[ -n "${DISPLAY:-}" ]] || { echo "No display (DISPLAY is not set): the integration test needs the VSX GUI." >&2; exit 2; }

    if [[ -z "${XAM_CPU_BEAMFORMER:-}" ]] && ! nvidia-smi -L > /dev/null 2>&1; then
        echo "   (no NVIDIA GPU found: using --cpu-beamformer)"
        export XAM_CPU_BEAMFORMER=1
    fi

    export XAM_DATA_PATH="$OUT/data"
    export XAM_SWEEP_FRAMES=2
    export XAM_BURST_CONFIRM=0           # no confirmation dialog
    export XAM_BURST_FRAMES="3,4,2"      # frames at the imaging voltage, at the burst voltage, at the imaging voltage
    if [[ $HARDWARE -eq 1 ]]; then
        echo "== Integration test on HARDWARE: the transducer will transmit at up to 2.5 V."
        echo "   Make sure it is in water or on a phantom."
        unset XAM_SIMULATE
        export XAM_SWEEP_VOLTAGES="1.6,2.0,2.4"   # at or below the 2.5 V start voltage
        export XAM_BURST_VOLTAGE=1.6              # burst below the imaging voltage: no collapse, but the voltage switch is checked
    else
        echo "== Integration test in simulation"
        export XAM_SIMULATE=1
        export XAM_SWEEP_VOLTAGES="2,3"
        export XAM_BURST_VOLTAGE=3
    fi

    run_matlab "$OUT/integration.log" "${XAM_TEST_TIMEOUT:-1200}" -nosplash -nodesktop \
        -r "cd('$VANTAGE_ROOT'); activate; addpath('$TESTS/integration'); xam_integration_test"
    rc=$?
    sed -n '/integration test summary/,$p' "$OUT/integration.log" | grep "^\[TEST\]" | grep -v "=====" | sed 's/^\[TEST\] /   /'

    # errors VSX prints instead of throwing (processing errors, stopped recordings or sweeps)
    errors=$(grep -n -E "RUNACQ Has reported|^Error |^Error using|Sweep stopped|Recording stopped after|Recording: |could not|Could not" "$OUT/integration.log" \
             | grep -v "stopped by user")
    if [[ -n "$errors" ]]; then
        echo "   FAIL  errors in the MATLAB output:"; echo "$errors" | head -20 | sed 's/^/         /'
        FAILED=1
    fi
    [[ $rc -eq 0 ]] || FAILED=1
fi

# ------------------------------------------------------------------- summary
[[ $KEEP_DATA -eq 1 ]] || rm -rf "$OUT/data"
if [[ $FAILED -eq 0 ]]; then
    echo "== ALL TESTS PASSED   (logs: $OUT)"
else
    echo "== TESTS FAILED       (logs: $OUT)"
fi
exit $FAILED
