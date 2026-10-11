#!/usr/bin/env python3
import pathlib, plistlib, subprocess, sys
app, profile = map(pathlib.Path, sys.argv[1:])
p = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile)], stderr=subprocess.DEVNULL))
info = plistlib.loads((app/'Info.plist').read_bytes())
identifier = p['Entitlements']['application-identifier']
if identifier.split('.', 1)[1] != info['CFBundleIdentifier']:
    raise SystemExit('Provisioning profile does not match the app bundle identifier')
(app/'embedded.mobileprovision').write_bytes(profile.read_bytes())
entitlements = app.parent/'signing.entitlements'
entitlements.write_bytes(plistlib.dumps(p['Entitlements']))
subprocess.run(['codesign', '--force', '--sign', 'Apple Development', '--entitlements', str(entitlements), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
