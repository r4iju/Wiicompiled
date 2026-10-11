#!/usr/bin/env bash
# Acquire a pooled TV first: sim acquire tv
# Run this script with its UDID. Release afterward: sim release <UDID>
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $# -lt 1 || $# -gt 2 || ${1:-} == --help ]]; then
    echo 'Usage: run-simulator.command <pooled-tvOS-simulator-UDID> [--automation]'
    echo 'Build first with Launcher/local-build-tvos-simulator.command [--automation].'
    echo 'The simulator lease belongs to the caller; use sim release <UDID> when finished.'
    exit 0
fi
udid=$1; automation=${2:-}
[[ -z "$automation" || "$automation" == --automation ]] || { echo 'Unknown option' >&2; exit 2; }
# simctl accepts simulator UUIDs only. Check the runtime too, to avoid using an iPhone pool.
xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json,sys
udid=sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["udid"] == udid and "tvOS" in runtime: sys.exit(0)
sys.exit("The UDID must identify an available tvOS Simulator")
' "$udid"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
app="$root/build-tvos-simulator/WiiCompiled.app"
[[ -f "$app/WiiCompiled" ]] || { echo 'Build the tvOS Simulator app first' >&2; exit 1; }
if [[ -n "$automation" ]]; then
    strings "$app/WiiCompiled" | /usr/bin/grep -F 'SDL virtual gamepad attached' > /dev/null || {
        echo 'Rebuild with --automation before using the diagnostic input channel' >&2; exit 1;
    }
fi
xcrun simctl terminate "$udid" xyz.raiju.WiiCompiled.simulator 2>/dev/null || true
xcrun simctl install "$udid" "$app"
# Installation can change the data-container UUID. Resolve it after installing.
sim_data_dir=$(xcrun simctl get_app_container "$udid" xyz.raiju.WiiCompiled.simulator data)
if [[ -n "$automation" ]]; then
    /usr/bin/python3 -c 'from pathlib import Path; import sys; Path(sys.argv[1]).write_bytes(bytes(4))' "$sim_data_dir/tmp/simulator-input.bin"
    echo "Diagnostic input: $sim_data_dir/tmp/simulator-input.bin"
    SIMCTL_CHILD_MKW_SIMULATOR_INPUT="$sim_data_dir/tmp/simulator-input.bin" \
        xcrun simctl launch --console-pty "$udid" xyz.raiju.WiiCompiled.simulator
else
    xcrun simctl launch --console-pty "$udid" xyz.raiju.WiiCompiled.simulator
fi
