#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# == 2 ]] || { echo 'Usage: install-device.command <Apple-TV-UDID> <development.mobileprovision>' >&2; exit 2; }
udid=$1; profile=$2
/usr/bin/python3 - "$profile" "$udid" <<'PY'
import datetime, plistlib, subprocess, sys
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
if 'tvOS' not in p.get('Platform',[]) or sys.argv[2] not in p.get('ProvisionedDevices',[]):
    raise SystemExit('Profile must support tvOS and include the requested Apple TV')
if p['ExpirationDate'] <= datetime.datetime.utcnow():
    raise SystemExit('Development profile has expired')
PY
app="$root/build-tvos-device/WiiCompiled.app"
/usr/bin/python3 "$root/Launcher/tvos/sign-device.py" "$app" "$profile"
xcrun devicectl device install app --device "$udid" "$app"
