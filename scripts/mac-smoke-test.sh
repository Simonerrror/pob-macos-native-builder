#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

ensure_metadata_exists

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

[[ -d "$bundle_dir" ]] || { printf 'Missing app bundle: %s\n' "$bundle_dir" >&2; exit 1; }
[[ -x "$launcher" ]] || { printf 'Missing launcher: %s\n' "$launcher" >&2; exit 1; }
[[ -x "$binary" ]] || { printf 'Missing runtime binary: %s\n' "$binary" >&2; exit 1; }
[[ -f "$payload_launch" ]] || { printf 'Missing Launch.lua payload: %s\n' "$payload_launch" >&2; exit 1; }
[[ -f "$metadata_file" ]] || { printf 'Missing version metadata: %s\n' "$metadata_file" >&2; exit 1; }
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
  python3 - "$launcher" <<'PY'
import subprocess
import sys
import time

launcher = sys.argv[1]
proc = subprocess.Popen([launcher], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(8)
if proc.poll() is not None:
    raise SystemExit(proc.returncode or 1)
proc.terminate()
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait(timeout=5)
PY
fi

log "Native smoke test passed"
