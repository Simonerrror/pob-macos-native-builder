#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SELF_DIR}/.." && pwd)"
RESOURCES_DIR="${APP_DIR}/Resources"
METADATA_FILE="${RESOURCES_DIR}/metadata/version.json"
SYNC_STAMP_FILE="${RESOURCES_DIR}/metadata/bundle-sync-stamp"
PAYLOAD_DIR="${RESOURCES_DIR}/payload/current"
RUNTIME_BIN="${RESOURCES_DIR}/runtime/bin/rusty-path-of-building"
RUNTIME_LIB_DIR="${RESOURCES_DIR}/runtime/lib"
APP_SUPPORT_ROOT="${POB_MAC_SUPPORT_DIR:-${HOME}/Library/Application Support/Path of Building}"
BUILDS_DIR="${POB_BUILDS_HOST_DIR:-${HOME}/Documents/Path of Building/Builds}"
BASE_APP_SUPPORT_DIR="$(dirname "$APP_SUPPORT_ROOT")"

read_metadata() {
  python3 - "$METADATA_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

print(payload["version_id"])
print(payload["game"])
print(payload["rusty"]["version"])
PY
}

metadata_values=()
while IFS= read -r line; do
  metadata_values+=("$line")
done < <(read_metadata)
VERSION_ID="${metadata_values[0]}"
GAME="${POB_MAC_GAME:-${metadata_values[1]}}"
RUSTY_VERSION="${metadata_values[2]}"
BUNDLE_STAMP="$VERSION_ID"

if [[ -f "$SYNC_STAMP_FILE" ]]; then
  BUNDLE_STAMP="$(<"$SYNC_STAMP_FILE")"
fi

if [[ "$GAME" == "poe2" ]]; then
  SCRIPT_DIR="${BASE_APP_SUPPORT_DIR}/RustyPathOfBuilding2"
else
  SCRIPT_DIR="${BASE_APP_SUPPORT_DIR}/RustyPathOfBuilding1"
fi

VERSIONS_ROOT="${APP_SUPPORT_ROOT}/versions"
VERSION_DIR="${VERSIONS_ROOT}/${VERSION_ID}"
CURRENT_LINK="${APP_SUPPORT_ROOT}/current"
USERDATA_ROOT="${APP_SUPPORT_ROOT}/userdata"
VERSION_MARKER="${VERSION_DIR}/.bundle-version"
SCRIPT_VERSION_MARKER="${SCRIPT_DIR}/.bundle-version"

mkdir -p "$VERSIONS_ROOT" "$USERDATA_ROOT" "$BUILDS_DIR" "$SCRIPT_DIR"

if [[ -d "${SCRIPT_DIR}/userdata" ]] && [[ ! -e "${USERDATA_ROOT}/Path of Building" ]]; then
  rsync -a "${SCRIPT_DIR}/userdata/" "${USERDATA_ROOT}/"
fi

if [[ ! -f "$VERSION_MARKER" ]] || [[ "$(<"$VERSION_MARKER")" != "$BUNDLE_STAMP" ]]; then
  TMP_DIR="${VERSION_DIR}.tmp.$$"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  rsync -a --delete "${PAYLOAD_DIR}/" "${TMP_DIR}/"
  rm -f "${TMP_DIR}/userdata" "${TMP_DIR}/Builds" "${USERDATA_ROOT}/Builds"
  ln -sfn "$USERDATA_ROOT" "${TMP_DIR}/userdata"
  ln -sfn "$BUILDS_DIR" "${TMP_DIR}/Builds"
  ln -sfn "$BUILDS_DIR" "${USERDATA_ROOT}/Builds"
  printf '%s' "$RUSTY_VERSION" > "${TMP_DIR}/rpob.version"
  printf '%s\n' "$BUNDLE_STAMP" > "${TMP_DIR}/.bundle-version"
  rm -rf "$VERSION_DIR"
  mv "$TMP_DIR" "$VERSION_DIR"
fi

if [[ ! -f "$SCRIPT_VERSION_MARKER" ]] || [[ "$(<"$SCRIPT_VERSION_MARKER")" != "$BUNDLE_STAMP" ]]; then
  TMP_SCRIPT_DIR="${SCRIPT_DIR}.tmp.$$"
  rm -rf "$TMP_SCRIPT_DIR"
  mkdir -p "$TMP_SCRIPT_DIR"
  rsync -a --delete "${PAYLOAD_DIR}/" "${TMP_SCRIPT_DIR}/"
  rm -rf "${TMP_SCRIPT_DIR}/userdata" "${TMP_SCRIPT_DIR}/Builds"
  ln -sfn "$USERDATA_ROOT" "${TMP_SCRIPT_DIR}/userdata"
  ln -sfn "$BUILDS_DIR" "${TMP_SCRIPT_DIR}/Builds"
  printf '%s' "$RUSTY_VERSION" > "${TMP_SCRIPT_DIR}/rpob.version"
  printf '%s\n' "$BUNDLE_STAMP" > "${TMP_SCRIPT_DIR}/.bundle-version"
  rm -rf "$SCRIPT_DIR"
  mv "$TMP_SCRIPT_DIR" "$SCRIPT_DIR"
fi

ln -sfn "$VERSION_DIR" "$CURRENT_LINK"

export LUA_PATH="${CURRENT_LINK}/share/lua/5.1/?.lua;${CURRENT_LINK}/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="${CURRENT_LINK}/lib/lua/5.1/?.so;;"
export DYLD_FALLBACK_LIBRARY_PATH="${RUNTIME_LIB_DIR}${DYLD_FALLBACK_LIBRARY_PATH:+:${DYLD_FALLBACK_LIBRARY_PATH}}"

cd "$CURRENT_LINK"
exec "$RUNTIME_BIN" "$GAME" "$@"
