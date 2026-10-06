#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

launch_smoke=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch)
      launch_smoke=1
      ;;
    *)
      printf 'Usage: %s [--launch]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

bundle_dir="${POB_MAC_BUNDLE_PATH}"
launcher="${bundle_dir}/Contents/MacOS/${POB_MAC_APP_NAME}"
binary="${bundle_dir}/Contents/Resources/runtime/bin/rusty-path-of-building"
payload_launch="${bundle_dir}/Contents/Resources/payload/current/Launch.lua"
metadata_file="${bundle_dir}/Contents/Resources/metadata/version.json"
bundle_stamp_file="${bundle_dir}/Contents/Resources/metadata/bundle-sync-stamp"

[[ -d "$bundle_dir" ]] || { printf 'Missing app bundle: %s\n' "$bundle_dir" >&2; exit 1; }
[[ -x "$launcher" ]] || { printf 'Missing launcher: %s\n' "$launcher" >&2; exit 1; }
[[ -x "$binary" ]] || { printf 'Missing runtime binary: %s\n' "$binary" >&2; exit 1; }
[[ -f "$payload_launch" ]] || { printf 'Missing Launch.lua payload: %s\n' "$payload_launch" >&2; exit 1; }
[[ -f "$metadata_file" ]] || { printf 'Missing version metadata: %s\n' "$metadata_file" >&2; exit 1; }
[[ -f "$bundle_stamp_file" ]] || { printf 'Missing bundle sync stamp: %s\n' "$bundle_stamp_file" >&2; exit 1; }
plutil -lint "${bundle_dir}/Contents/Info.plist" >/dev/null
python3 - "$metadata_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

assert payload["pob"]["tag"].startswith("v")
assert payload["rusty"]["tag"].startswith("v")
assert payload["version_id"]
PY

if [[ "$launch_smoke" -eq 1 ]]; then
  python3 - "$launcher" "$metadata_file" "$bundle_stamp_file" <<'PY'
import json
import os
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

launcher = sys.argv[1]
metadata_file = Path(sys.argv[2])
bundle_stamp_file = Path(sys.argv[3])
with metadata_file.open("r", encoding="utf-8") as handle:
    payload = json.load(handle)

expected_version = payload["pob"]["version"]
expected_bundle_stamp = bundle_stamp_file.read_text(encoding="utf-8").strip()
configured_support_dir = (
    os.environ.get("POB_MAC_SUPPORT_DIR")
    or payload.get("app", {}).get("support_dir")
    or str(Path.home() / "Library/Application Support/Path of Building")
)
script_dir_name = "RustyPathOfBuilding2" if payload["game"] == "poe2" else "RustyPathOfBuilding1"
script_dir = Path(configured_support_dir).expanduser().parent / script_dir_name
timeout_seconds = float(os.environ.get("POB_MAC_SMOKE_TIMEOUT_SECONDS", "45"))
proc = subprocess.Popen([launcher], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
deadline = time.time() + timeout_seconds
bundle_version = None
manifest_version = None
manifest_branch = None
manifest_platform = None

try:
    while time.time() < deadline:
        if proc.poll() is not None:
            raise SystemExit(proc.returncode or 1)

        marker_path = script_dir / ".bundle-version"
        manifest_path = script_dir / "manifest.xml"
        if marker_path.exists() and manifest_path.exists():
            bundle_version = marker_path.read_text(encoding="utf-8").strip()
            manifest_root = ET.parse(manifest_path).getroot()
            version_node = manifest_root.find("Version")
            manifest_version = version_node.attrib["number"]
            manifest_branch = version_node.attrib.get("branch")
            manifest_platform = version_node.attrib.get("platform")
            if (
                bundle_version == expected_bundle_stamp
                and manifest_version == expected_version
                and manifest_branch == "master"
                and manifest_platform == "macos"
            ):
                break

        time.sleep(1)
    else:
        raise SystemExit(f"Timed out waiting for {script_dir} to reach {expected_version}")
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)

assert bundle_version == expected_bundle_stamp, (bundle_version, expected_bundle_stamp)
assert manifest_version == expected_version, (manifest_version, expected_version)
assert manifest_branch == "master", manifest_branch
assert manifest_platform == "macos", manifest_platform
PY
fi

log "Native smoke test passed"
