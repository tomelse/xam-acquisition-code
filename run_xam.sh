#!/usr/bin/env bash
# Start the xAM imaging sequence from the terminal.
#
# Usage: ./run_xam.sh [options]
#
#   --sweep VOLTAGES     add a 'Voltage sweep' button that sweeps the transmit voltage,
#                        twice, and plots the mean xAM signal per voltage.
#                        VOLTAGES: start:step:stop (e.g. 1.6:0.4:6) or a list (2,3,5)
#   --sweep-frames N     frames recorded per voltage (default 5)
#   --sweep-save images|rf  what the sweep saves per voltage (default images;
#                        rf is ~190 MB per frame)
#   --save images|rf     initial save mode for Save Data and Record (default images)
#   --sim                simulation mode (no hardware needed)
#   --cpu-beamformer     slow MATLAB beamformer, no MLBFXWave needed
#   -h, --help           show this help
#
# Override the defaults with environment variables, e.g.
#   VANTAGE_ROOT=~/Documents/Code/VantageNXT-2.3.1-p1 ./run_xam.sh
# The MATLAB command window stays in this terminal; quit MATLAB with `exit`.
set -euo pipefail

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || { echo "Option $1 needs a value" >&2; exit 1; }; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sweep)          need_value "$@"; export XAM_SWEEP_VOLTAGES="$2"; shift 2 ;;
        --sweep-frames)   need_value "$@"; export XAM_SWEEP_FRAMES="$2"; shift 2 ;;
        --sweep-save)     need_value "$@"
                          [[ "$2" == images || "$2" == rf ]] || { echo "--sweep-save must be images or rf" >&2; exit 1; }
                          export XAM_SWEEP_SAVE="$2"; shift 2 ;;
        --save)           need_value "$@"
                          [[ "$2" == images || "$2" == rf ]] || { echo "--save must be images or rf" >&2; exit 1; }
                          export XAM_SAVE_MODE="$2"; shift 2 ;;
        --sim)            export XAM_SIMULATE=1; shift ;;
        --cpu-beamformer) export XAM_CPU_BEAMFORMER=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATLAB="${MATLAB:-$HOME/MATLAB2024a/bin/matlab}"                       # NXT 2.2/2.3 need R2024a
VANTAGE_ROOT="${VANTAGE_ROOT:-$HOME/Documents/Code/VantageNXT-2.3.2-p2}"

[[ -x "$MATLAB" ]] || { echo "MATLAB not found: $MATLAB (set MATLAB=...)" >&2; exit 1; }
[[ -f "$VANTAGE_ROOT/VSX.m" ]] || { echo "Vantage software not found: $VANTAGE_ROOT (set VANTAGE_ROOT=...)" >&2; exit 1; }

[[ -n "${XAM_SWEEP_VOLTAGES:-}" ]] && echo "Voltage sweep: ${XAM_SWEEP_VOLTAGES} V, ${XAM_SWEEP_FRAMES:-5} frames per voltage, 2 passes, saving ${XAM_SWEEP_SAVE:-images}. Press 'Voltage sweep' in VSX to start."
[[ "${XAM_SIMULATE:-}" == 1 ]] && echo "Simulation mode."

# activate must run from the Vantage root; xAM_imaging.m then changes there itself before VSX
exec "$MATLAB" -nosplash -nodesktop -r "cd('$VANTAGE_ROOT'); activate; run('$REPO/xAM_imaging.m')"
