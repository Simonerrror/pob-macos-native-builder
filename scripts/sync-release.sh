#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/.cache"
DOWNLOAD_ROOT="${CACHE_ROOT}/downloads"
RUNTIME_ROOT="${CACHE_ROOT}/runtime"
STATE_ROOT="${REPO_ROOT}/.state"
API_ROOT="https://api.github.com/repos/PathOfBuildingCommunity/PathOfBuilding/releases"
USER_AGENT="pob-local-wrapper"
mode="activate"
release_ref="latest"

usage() {
  cat <<'EOF'
Usage: ./scripts/sync-release.sh [--prefetch] [latest|vX.Y.Z]

Options:
  --prefetch   Download and extract the release into cache without switching
               .cache/runtime/current or .state/current-release.
  -h, --help   Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefetch)
      mode="prefetch"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ "$release_ref" != "latest" ]]; then
        printf 'Only one release reference is allowed.\n\n' >&2
        usage >&2
        exit 1
      fi
      release_ref="$1"
      shift
      ;;
  esac
done

log() {
  printf '[sync-release] %s\n' "$*"
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

fetch_release_json() {
  local ref="$1"
  local url
  if [[ "$ref" == "latest" ]]; then
    url="${API_ROOT}/latest"
  else
    url="${API_ROOT}/tags/${ref}"
  fi
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: ${USER_AGENT}" \
    "$url"
}

extract_release_fields() {
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
asset = next((a for a in data.get("assets", []) if a.get("name") == "PathOfBuildingCommunity-Portable.zip"), None)
if asset is None:
    raise SystemExit("Portable release asset PathOfBuildingCommunity-Portable.zip not found")

digest = asset.get("digest") or ""
if digest.startswith("sha256:"):
    digest = digest.split(":", 1)[1]

print(data["tag_name"])
print(asset["browser_download_url"])
print(digest)
print(data.get("published_at") or "")
'
}

ensure_directories() {
  mkdir -p "$DOWNLOAD_ROOT" "$RUNTIME_ROOT" "$STATE_ROOT"
}

download_release_zip() {
  local url="$1"
  local target="$2"
  log "Downloading ${url}"
  curl -fL -C - --retry 3 --retry-delay 2 --retry-connrefused \
    -H "User-Agent: ${USER_AGENT}" \
    -o "$target" \
    "$url"
}

verify_digest() {
  local file="$1"
  local expected="$2"
  if [[ -z "$expected" ]]; then
    return 0
  fi
  local actual
  actual="$(hash_file "$file")"
  if [[ "$actual" != "$expected" ]]; then
    log "Digest mismatch for $file"
    log "Expected: $expected"
    log "Actual:   $actual"
    exit 1
  fi
}

extract_zip() {
  local zip_path="$1"
  local dest="$2"
  local tmp="${dest}.tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  unzip -q "$zip_path" -d "$tmp"
  rm -rf "$dest"
  mv "$tmp" "$dest"
}

write_state() {
  local tag="$1"
  local published_at="$2"
  cat >"${STATE_ROOT}/current-release" <<EOF
${tag}
EOF
  cat >"${STATE_ROOT}/current-release.json" <<EOF
{"tag":"${tag}","published_at":"${published_at}"}
EOF
}

write_prefetch_state() {
  local tag="$1"
  local published_at="$2"
  cat >"${STATE_ROOT}/prefetched-release" <<EOF
${tag}
EOF
  cat >"${STATE_ROOT}/prefetched-release.json" <<EOF
{"tag":"${tag}","published_at":"${published_at}"}
EOF
}

update_current_symlink() {
  local tag="$1"
  ln -sfn "${RUNTIME_ROOT}/${tag}" "${RUNTIME_ROOT}/current"
}

ensure_directories
release_json="$(fetch_release_json "$release_ref")"
release_fields="$(printf '%s' "$release_json" | extract_release_fields)"

tag="$(printf '%s\n' "$release_fields" | sed -n '1p')"
download_url="$(printf '%s\n' "$release_fields" | sed -n '2p')"
sha256="$(printf '%s\n' "$release_fields" | sed -n '3p')"
published_at="$(printf '%s\n' "$release_fields" | sed -n '4p')"

download_dir="${DOWNLOAD_ROOT}/${tag}"
runtime_dir="${RUNTIME_ROOT}/${tag}"
zip_path="${download_dir}/PathOfBuildingCommunity-Portable.zip"

mkdir -p "$download_dir"

if [[ -f "$zip_path" ]]; then
  log "Reusing existing archive at ${zip_path}"
else
  download_release_zip "$download_url" "$zip_path"
fi

verify_digest "$zip_path" "$sha256"

if [[ -d "$runtime_dir" ]]; then
  log "Runtime already extracted at ${runtime_dir}"
else
  log "Extracting ${zip_path} -> ${runtime_dir}"
  extract_zip "$zip_path" "$runtime_dir"
fi

if [[ "$mode" == "prefetch" ]]; then
  write_prefetch_state "$tag" "$published_at"
  log "Prefetched PoB release: ${tag}"
  log "Runtime path: ${runtime_dir}"
  log "Active runtime unchanged: ${RUNTIME_ROOT}/current"
else
  update_current_symlink "$tag"
  write_state "$tag" "$published_at"
  log "Current PoB release: ${tag}"
  log "Runtime path: ${runtime_dir}"
  log "Symlinked current runtime: ${RUNTIME_ROOT}/current"
fi
