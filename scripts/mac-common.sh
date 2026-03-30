#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/.cache/macos"
UPSTREAM_ROOT="${CACHE_ROOT}/upstream"
DOWNLOADS_ROOT="${CACHE_ROOT}/downloads"
BUILD_ROOT="${CACHE_ROOT}/build"
TOOLS_ROOT="${CACHE_ROOT}/tools"
DIST_ROOT="${REPO_ROOT}/dist"
APP_STATE_ROOT="${REPO_ROOT}/.state"
MAC_STATE_ROOT="${APP_STATE_ROOT}/macos"
LOG_DIR="${APP_STATE_ROOT}/logs"
VERSION_METADATA_FILE="${MAC_STATE_ROOT}/current-version.json"
LAST_REFRESH_FILE="${MAC_STATE_ROOT}/last-refresh"
LOCK_DIR="${MAC_STATE_ROOT}/refresh.lock"
DEFAULT_BUILD_DIR="/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds"

POB_MAC_APP_NAME="${POB_MAC_APP_NAME:-Path of Building}"
POB_MAC_APP_BUNDLE_ID="${POB_MAC_APP_BUNDLE_ID:-dev.sergio.pathofbuilding.local}"
POB_MAC_GAME="${POB_MAC_GAME:-poe1}"
POB_MAC_SUPPORT_DIR="${POB_MAC_SUPPORT_DIR:-${HOME}/Library/Application Support/Path of Building}"
POB_MAC_BUNDLE_PATH="${POB_MAC_BUNDLE_PATH:-${DIST_ROOT}/${POB_MAC_APP_NAME}.app}"
POB_MAC_RUSTY_REPO="${POB_MAC_RUSTY_REPO:-meehl/rusty-path-of-building}"
POB_MAC_COMPAT_REPO="${POB_MAC_COMPAT_REPO:-meehl/rusty-pob-manifest}"
POB_MAC_BUILDS_DIR="${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}"
POB_MAC_DKJSON_SHA256="${POB_MAC_DKJSON_SHA256:-3d8de09cd43a60a005ac769ee1cedc515952c892d63cba9ac925ed02afc98091}"
POB_MAC_LUAUTF8_SHA256="${POB_MAC_LUAUTF8_SHA256:-37901bc127c4afe9f611bba58af7b12eda6599fc270e1706e2f767807dfacd82}"
POB_MAC_LUASOCKET_SHA256="${POB_MAC_LUASOCKET_SHA256:-f4a207f50a3f99ad65def8e29c54ac9aac668b216476f7fae3fae92413398ed2}"
POB_MAC_LUACURL_SHA256="${POB_MAC_LUACURL_SHA256:-aba40511a7cac4422c0238d1db42b2124ea5a727b0745f7f434f3dc119cbb2db}"

log() {
  printf '[mac-native] %s\n' "$*"
}

game_repo() {
  if [[ "$POB_MAC_GAME" == "poe2" ]]; then
    printf '%s\n' "${POB_MAC_POB_REPO:-PathOfBuildingCommunity/PathOfBuilding-PoE2}"
  else
    printf '%s\n' "${POB_MAC_POB_REPO:-PathOfBuildingCommunity/PathOfBuilding}"
  fi
}

compat_name() {
  if [[ "$POB_MAC_GAME" == "poe2" ]]; then
    printf '%s\n' 'Compatibility_pob2.lua'
  else
    printf '%s\n' 'Compatibility_pob1.lua'
  fi
}

ensure_mac_dirs() {
  mkdir -p \
    "$UPSTREAM_ROOT" \
    "$DOWNLOADS_ROOT" \
    "$BUILD_ROOT" \
    "$TOOLS_ROOT" \
    "$DIST_ROOT" \
    "$MAC_STATE_ROOT" \
    "$LOG_DIR" \
    "$POB_MAC_BUILDS_DIR"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$cmd" >&2
    exit 1
  fi
}

github_api() {
  local url="$1"
  curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$url"
}

latest_pob_tag() {
  github_api "https://api.github.com/repos/$(game_repo)/releases/latest" | jq -r '.tag_name'
}

resolve_pob_tag() {
  local raw="${1:-latest}"
  if [[ "$raw" == "latest" ]]; then
    latest_pob_tag
  elif [[ "$raw" =~ ^v[0-9][0-9A-Za-z._-]*$ ]]; then
    printf '%s\n' "$raw"
  else
    printf 'Invalid PoB tag: %s\n' "$raw" >&2
    exit 1
  fi
}

strip_v() {
  printf '%s\n' "${1#v}"
}

extract_github_tarball() {
  local repo="$1"
  local ref="$2"
  local dest="$3"
  local archive_name archive_path
  archive_name="${repo//\//-}-${ref}.tar.gz"
  archive_path="${DOWNLOADS_ROOT}/${archive_name}"

  if [[ -f "${dest}/.pob-extracted-ref" ]] && [[ "$(<"${dest}/.pob-extracted-ref")" == "$ref" ]]; then
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  log "Downloading ${repo}@${ref}"
  mkdir -p "$DOWNLOADS_ROOT"
  local url
  url="https://codeload.github.com/${repo}/tar.gz/refs/tags/${ref}"

  if [[ -f "$archive_path" ]]; then
    if ! curl -fL -C - \
      --retry 10 \
      --retry-delay 2 \
      --retry-all-errors \
      -o "$archive_path" \
      "$url"; then
      log "Resume failed for ${archive_name}; retrying from scratch"
      rm -f "$archive_path"
      curl -fL \
        --retry 10 \
        --retry-delay 2 \
        --retry-all-errors \
        -o "$archive_path" \
        "$url"
    fi
  else
    curl -fL \
      --retry 10 \
      --retry-delay 2 \
      --retry-all-errors \
      -o "$archive_path" \
      "$url"
  fi
  tar -xzf "$archive_path" -C "$tmpdir"

  local extracted_root
  extracted_root="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "$extracted_root" ]]; then
    printf 'Failed to extract tarball for %s@%s\n' "$repo" "$ref" >&2
    exit 1
  fi

  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$extracted_root" "$dest"
  printf '%s\n' "$ref" > "${dest}/.pob-extracted-ref"
  rm -rf "$tmpdir"
}

download_with_sha256() {
  local url="$1"
  local output="$2"
  local expected_sha="$3"

  mkdir -p "$(dirname "$output")"
  if [[ -f "$output" ]]; then
    local current_sha
    current_sha="$(shasum -a 256 "$output" | awk '{print $1}')"
    if [[ "$current_sha" == "$expected_sha" ]]; then
      return 0
    fi
    rm -f "$output"
  fi

  log "Downloading $(basename "$output")"
  curl -fL --retry 3 --retry-delay 2 -o "$output" "$url"

  local actual_sha
  actual_sha="$(shasum -a 256 "$output" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    printf 'Checksum mismatch for %s\nExpected: %s\nActual:   %s\n' "$output" "$expected_sha" "$actual_sha" >&2
    exit 1
  fi
}

compat_file_path() {
  printf '%s\n' "${DOWNLOADS_ROOT}/$(compat_name)"
}

download_compatibility_file() {
  local target
  target="$(compat_file_path)"
  curl -fsSL "https://raw.githubusercontent.com/${POB_MAC_COMPAT_REPO}/main/$(compat_name)" -o "$target"
}

minimum_rusty_version_for_pob() {
  local pob_version="$1"
  local compat_file="$2"
  python3 - "$pob_version" "$compat_file" <<'PY'
import re
import sys

pob_version = sys.argv[1]
compat_path = sys.argv[2]
compat = {}
pattern = re.compile(r'compat\["([^"]+)"\]\s*=\s*"([^"]+)"')
with open(compat_path, "r", encoding="utf-8") as handle:
    for line in handle:
        match = pattern.search(line)
        if match:
            compat[match.group(1)] = match.group(2)

value = compat.get(pob_version)
if not value:
    raise SystemExit(f"Unable to resolve compatibility mapping for PoB {pob_version}")

print(value)
PY
}

resolve_rusty_tag() {
  local minimum_version="$1"
  local releases_json

  if [[ -n "${POB_MAC_RUSTY_TAG:-}" ]]; then
    printf '%s\n' "$POB_MAC_RUSTY_TAG"
    return 0
  fi

  releases_json="$(github_api "https://api.github.com/repos/${POB_MAC_RUSTY_REPO}/releases?per_page=100")"

  python3 - "$minimum_version" "$releases_json" <<'PY'
import json
import re
import sys

def parse(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))

minimum = parse(sys.argv[1])
releases = json.loads(sys.argv[2])
best_tag = None
best_version = None

for release in releases:
    tag = release.get("tag_name") or ""
    if not re.match(r"^v\d+\.\d+\.\d+$", tag):
      continue
    parsed = parse(tag[1:])
    if parsed < minimum:
      continue
    if best_version is None or parsed > best_version:
      best_tag = tag
      best_version = parsed

if best_tag is None:
    raise SystemExit(f"No rusty-path-of-building release satisfies minimum {sys.argv[1]}")

print(best_tag)
PY
}

version_id_from_tags() {
  local pob_tag="$1"
  local rusty_tag="$2"
  printf '%s\n' "${pob_tag}--${rusty_tag}"
}

native_stage_dir() {
  printf '%s\n' "${BUILD_ROOT}/stage/$1"
}

native_runtime_dir() {
  printf '%s\n' "${BUILD_ROOT}/runtime/$1"
}

metadata_value() {
  local query="$1"
  jq -r "$query" "$VERSION_METADATA_FILE"
}

ensure_metadata_exists() {
  if [[ ! -f "$VERSION_METADATA_FILE" ]]; then
    printf 'Missing native metadata at %s\nRun ./scripts/mac-sync-upstream.sh latest first.\n' "$VERSION_METADATA_FILE" >&2
    exit 1
  fi
}

write_version_metadata() {
  local pob_tag="$1"
  local pob_version="$2"
  local pob_published_at="$3"
  local rusty_tag="$4"
  local rusty_version="$5"
  local rusty_published_at="$6"
  local minimum_rusty="$7"

  local version_id
  version_id="$(version_id_from_tags "$pob_tag" "$rusty_tag")"

  python3 - "$VERSION_METADATA_FILE" "$pob_tag" "$pob_version" "$pob_published_at" "$rusty_tag" "$rusty_version" "$rusty_published_at" "$minimum_rusty" "$version_id" "$POB_MAC_GAME" "$POB_MAC_APP_NAME" "$POB_MAC_APP_BUNDLE_ID" "$POB_MAC_SUPPORT_DIR" "$(game_repo)" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

(
    output_path,
    pob_tag,
    pob_version,
    pob_published_at,
    rusty_tag,
    rusty_version,
    rusty_published_at,
    minimum_rusty,
    version_id,
    game,
    app_name,
    bundle_id,
    support_dir,
    pob_repo,
) = sys.argv[1:]

payload = {
    "synced_at": datetime.now(timezone.utc).isoformat(),
    "game": game,
    "version_id": version_id,
    "pob": {
        "repo": pob_repo,
        "tag": pob_tag,
        "version": pob_version,
        "published_at": pob_published_at,
    },
    "rusty": {
        "repo": "meehl/rusty-path-of-building",
        "tag": rusty_tag,
        "version": rusty_version,
        "published_at": rusty_published_at,
        "minimum_required": minimum_rusty,
    },
    "app": {
        "name": app_name,
        "bundle_id": bundle_id,
        "support_dir": support_dir,
    },
    "local_patches": [
        "bundle-launcher",
        "userdata-symlink",
        "builds-symlink",
        "lua-cpath",
        "disable-in-app-update",
    ],
}

path = pathlib.Path(output_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

ensure_host_build_dependencies() {
  require_cmd brew
  require_cmd jq
  require_cmd python3
  require_cmd cargo
  require_cmd rustc
  require_cmd iconutil
  require_cmd plutil
  require_cmd otool
  require_cmd install_name_tool
  require_cmd rsync

  local formula
  for formula in luajit pkgconf luarocks; do
    if ! brew list --versions "$formula" >/dev/null 2>&1; then
      log "Installing Homebrew dependency: ${formula}"
      HOMEBREW_NO_AUTO_UPDATE=1 brew install "$formula"
    fi
  done
}

luajit_prefix() {
  brew --prefix luajit
}
