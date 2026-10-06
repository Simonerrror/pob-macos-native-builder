#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

make_bundle() {
  local bundle_dir="$1"
  local launcher_body="$2"
  local stamp="${3:-expected-stamp}"

  mkdir -p \
    "${bundle_dir}/Contents/MacOS" \
    "${bundle_dir}/Contents/Resources/runtime/bin" \
    "${bundle_dir}/Contents/Resources/payload/current" \
    "${bundle_dir}/Contents/Resources/metadata"

  python3 - "$bundle_dir/Contents/Info.plist" <<'PY'
import plistlib
import sys

payload = {
    "CFBundleExecutable": "Path of Building",
    "CFBundleIdentifier": "dev.test.pathofbuilding",
    "CFBundleName": "Path of Building",
    "CFBundlePackageType": "APPL",
}

with open(sys.argv[1], "wb") as handle:
    plistlib.dump(payload, handle)
PY

  printf '%s\n' 'print("fixture")' > "${bundle_dir}/Contents/Resources/payload/current/Launch.lua"
  printf '%s\n' "$stamp" > "${bundle_dir}/Contents/Resources/metadata/bundle-sync-stamp"
  printf '%s\n' '#!/usr/bin/env bash' 'sleep 60' > "${bundle_dir}/Contents/Resources/runtime/bin/rusty-path-of-building"
  chmod 755 "${bundle_dir}/Contents/Resources/runtime/bin/rusty-path-of-building"

  python3 - "${bundle_dir}/Contents/Resources/metadata/version.json" <<'PY'
import json
import sys

payload = {
    "game": "poe1",
    "version_id": "v9.9.9--v0.0.1",
    "pob": {"tag": "v9.9.9", "version": "9.9.9"},
    "rusty": {"tag": "v0.0.1", "version": "0.0.1"},
    "app": {"support_dir": ""},
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$launcher_body" > "${bundle_dir}/Contents/MacOS/Path of Building"
  chmod 755 "${bundle_dir}/Contents/MacOS/Path of Building"
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  "$@" &
  local pid=$!
  local deadline=$((SECONDS + timeout_seconds))
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.2
  done
  wait "$pid"
}

test_launch_smoke_uses_support_override() {
  local tmp bundle support launcher_body
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  bundle="${tmp}/Path of Building.app"
  support="${tmp}/isolated/Path of Building"
  launcher_body='
script_dir="$(dirname "$POB_MAC_SUPPORT_DIR")/RustyPathOfBuilding1"
mkdir -p "$script_dir"
printf "%s\n" "expected-stamp" > "$script_dir/.bundle-version"
cat > "$script_dir/manifest.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<PoBVersion><Version number="9.9.9" branch="master" platform="macos" /></PoBVersion>
XML
sleep 60
'
  make_bundle "$bundle" "$launcher_body"

  HOME="${tmp}/home" \
  POB_MAC_SUPPORT_DIR="$support" \
  POB_MAC_BUNDLE_PATH="$bundle" \
  POB_MAC_SMOKE_TIMEOUT_SECONDS=2 \
  run_with_timeout 8 "${REPO_ROOT}/scripts/mac-smoke-test.sh" --launch
}

test_launch_smoke_rejects_stale_bundle_stamp() {
  local tmp bundle launcher_body status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  bundle="${tmp}/Path of Building.app"
  launcher_body='
script_dir="${HOME}/Library/Application Support/RustyPathOfBuilding1"
mkdir -p "$script_dir"
printf "%s\n" "stale-stamp" > "$script_dir/.bundle-version"
cat > "$script_dir/manifest.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<PoBVersion><Version number="9.9.9" branch="master" platform="macos" /></PoBVersion>
XML
sleep 60
'
  make_bundle "$bundle" "$launcher_body" "expected-stamp"

  set +e
  HOME="${tmp}/home" \
  POB_MAC_BUNDLE_PATH="$bundle" \
  POB_MAC_SMOKE_TIMEOUT_SECONDS=2 \
  run_with_timeout 8 "${REPO_ROOT}/scripts/mac-smoke-test.sh" --launch >/dev/null 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "launch smoke accepted stale bundle stamp"
}

test_bundle_launcher_without_python() {
  local tmp bundle support
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  bundle="${tmp}/Path of Building.app"
  support="${tmp}/isolated/Path of Building"
  make_bundle "$bundle" 'exit 1'
  cp "$REPO_ROOT/macos/launcher.sh" "$bundle/Contents/MacOS/Path of Building"
  mkdir -p "$tmp/bin" "$tmp/builds"
  printf '%s\n' '#!/bin/bash' 'exit 99' > "$tmp/bin/python3"
  chmod +x "$tmp/bin/python3"
  printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$1" > "$POB_MAC_TEST_LOG"' \
    > "$bundle/Contents/Resources/runtime/bin/rusty-path-of-building"

  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  POB_MAC_SUPPORT_DIR="$support" \
  POB_BUILDS_HOST_DIR="$tmp/builds" \
  POB_MAC_TEST_LOG="$tmp/runtime.log" \
    bash "$bundle/Contents/MacOS/Path of Building"

  [[ "$(cat "$tmp/runtime.log")" == poe1 ]] || fail "launcher did not start the selected game"
  [[ "$(cat "$support/versions/v9.9.9--v0.0.1/.bundle-version")" == expected-stamp ]] || fail "launcher did not materialize the payload"
  [[ "$(readlink "$support/userdata/Builds")" == "$tmp/builds" ]] || fail "launcher did not preserve the configured builds path"
}

test_bundle_launcher_without_python
test_launch_smoke_uses_support_override
test_launch_smoke_rejects_stale_bundle_stamp

printf 'ok - mac smoke launch behavior\n'
