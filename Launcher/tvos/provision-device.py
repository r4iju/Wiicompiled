#!/usr/bin/env python3
"""Create an internal Apple development profile using an existing App Store Connect key and certificate."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import time


BUNDLE = "xyz.raiju.WiiCompiled.tvos"


def api_client():
    key_path = Path(os.environ["ASC_KEY_PATH"]).expanduser()
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    now = int(time.time())
    header = encode(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    message = header + b"." + payload
    signature = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", str(key_path)], input=message)
    # OpenSSL returns DER integers; JWT ES256 requires two fixed-width integers.
    offset = 2
    values = []
    for _ in range(2):
        length = signature[offset + 1]
        values.append(int.from_bytes(signature[offset + 2:offset + 2 + length], "big").to_bytes(32, "big"))
        offset += 2 + length
    token = (message + b"." + encode(b"".join(values))).decode()
    proxy = os.environ.get("APPLE_API_PROXY")
    if not proxy:
        raise RuntimeError("Set APPLE_API_PROXY to an authorized network route.")

    def call(path, method="GET", data=None):
        command = ["curl", "-q", "--silent", "--show-error", "--globoff", "--noproxy", "",
                   "--proxy", proxy, "--max-time", "45", "--request", method,
                   "--header", "@-",
                   "https://api.appstoreconnect.apple.com/v1/" + path]
        headers = ("Authorization: Bearer " + token + "\nContent-Type: application/json\n").encode()
        if data is not None:
            command += ["--data-binary", json.dumps(data)]
        result = json.loads(subprocess.check_output(command, input=headers))
        if "errors" in result:
            raise RuntimeError("; ".join(e.get("detail", e.get("title", "API error")) for e in result["errors"]))
        return result
    return call


def provision(udid=None, inspect=False, platform="tvOS", bundle_identifier=BUNDLE, display_name="WiiCompiled"):
    allowed_classes = {"APPLE_TV"} if platform == "tvOS" else {"IPHONE", "IPAD"}
    profile_type = "TVOS_APP_DEVELOPMENT" if platform == "tvOS" else "IOS_APP_DEVELOPMENT"
    api = api_client()
    devices = api("devices?limit=200")["data"]
    tvs = [device for device in devices if device["attributes"].get("deviceClass") in allowed_classes]
    if inspect:
        print(json.dumps([{"id": d["id"], **d["attributes"]} for d in tvs], indent=2))
        return
    if udid:
        matches = [d for d in devices if d["attributes"]["udid"] == udid]
        if matches:
            if matches[0]["attributes"].get("deviceClass") not in allowed_classes:
                raise RuntimeError("The supplied UDID does not match the requested device platform.")
            tvs = matches
        else:
            device = api("devices", "POST", {"data": {"type": "devices", "attributes": {"name": display_name, "udid": udid, "platform": "IOS"}}})["data"]
            if device["attributes"].get("deviceClass") not in allowed_classes:
                raise RuntimeError("Apple did not identify this UDID as the requested device platform.")
            tvs = [device]
    if not tvs:
        raise RuntimeError("No matching Apple device is registered. Pair it, then pass its UDID with --udid.")
    for device in tvs:
        if device["attributes"]["status"] == "DISABLED":
            api("devices/" + device["id"], "PATCH", {"data": {"type": "devices", "id": device["id"], "attributes": {"status": "ENABLED"}}})

    bundles = api("bundleIds?filter[identifier]=" + bundle_identifier)["data"]
    bundle = bundles[0] if bundles else api("bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {"identifier": bundle_identifier, "name": display_name, "platform": "IOS"}}})["data"]
    certificate_name = os.environ.get("ASC_CERTIFICATE_NAME", "Apple Development")
    local_pem = subprocess.check_output(["security", "find-certificate", "-c", certificate_name, "-p"])
    local_cert = subprocess.check_output(["openssl", "x509", "-outform", "DER"], input=local_pem)
    certificates = api("certificates?limit=200")["data"]
    matches = [c for c in certificates if c["attributes"]["certificateType"] == "DEVELOPMENT" and base64.b64decode(c["attributes"]["certificateContent"]) == local_cert]
    if not matches:
        raise RuntimeError("The installed Apple Development certificate does not match an active developer certificate.")
    name = display_name + " Development " + time.strftime("%Y%m%d-%H%M%S")
    profile = api("profiles", "POST", {"data": {
        "type": "profiles", "attributes": {"name": name, "profileType": profile_type},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": matches[0]["id"]}]},
            "devices": {"data": [{"type": "devices", "id": device["id"]} for device in tvs]},
        },
    }})["data"]["attributes"]
    directory = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (profile["uuid"] + ".mobileprovision")
    path.write_bytes(base64.b64decode(profile["profileContent"]))
    # The deployment script consumes only the UUID on stdout.
    print(profile["uuid"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--platform", choices=["tvOS", "iOS"], default="tvOS")
    parser.add_argument("--bundle", default=BUNDLE)
    parser.add_argument("--name", default="WiiCompiled")
    arguments = parser.parse_args()
    provision(arguments.udid, arguments.inspect, arguments.platform, arguments.bundle, arguments.name)
