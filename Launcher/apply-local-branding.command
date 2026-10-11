#!/usr/bin/env bash
# Optional personal artwork and display name never enter the source tree.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 2 ]] || { echo 'Usage: apply-local-branding.command {macos|tvos-simulator|tvos-device} APP' >&2; exit 2; }
platform=$1; app=$2; branding="$root/local-branding"
case "$platform" in
    macos) plist="$app/Contents/Info.plist"; resources="$app/Contents/Resources" ;;
    tvos-simulator|tvos-device) plist="$app/Info.plist"; resources="$app" ;;
    *) echo 'Unsupported branding platform' >&2; exit 2 ;;
esac
[[ -f "$plist" ]] || { echo "Missing app plist: $plist" >&2; exit 1; }
[[ -d "$branding" ]] || exit 0
if [[ "$platform" == macos && -f "$branding/AppIcon.icns" ]]; then
    ditto "$branding/AppIcon.icns" "$resources/LocalAppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile LocalAppIcon' "$plist" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string LocalAppIcon' "$plist"
elif [[ "$platform" == tvos-* && -d "$branding/Assets.xcassets" ]]; then
    partial=$(mktemp)
    trap 'rm -f "$partial"' EXIT
    xcrun actool "$branding/Assets.xcassets" --compile "$resources" \
        --platform "$([[ "$platform" == tvos-device ]] && echo appletvos || echo appletvsimulator)" --minimum-deployment-target 27.0 \
        --target-device tv --app-icon AppIcon --output-partial-info-plist "$partial"
    /usr/bin/python3 - "$plist" "$partial" <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
data.update(plistlib.loads(Path(sys.argv[2]).read_bytes()))
path.write_bytes(plistlib.dumps(data))
PY
fi
if [[ -f "$branding/display-name.txt" ]]; then
    /usr/bin/python3 - "$plist" "$branding/display-name.txt" <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
name = Path(sys.argv[2]).read_text().strip()
if not name or '\n' in name:
    raise SystemExit('Local display name must be one nonempty line')
data = plistlib.loads(path.read_bytes())
data['CFBundleDisplayName'] = data['CFBundleName'] = name
path.write_bytes(plistlib.dumps(data))
PY
fi
