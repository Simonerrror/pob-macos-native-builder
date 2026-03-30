#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

usage() {
  printf 'Usage: %s [latest|vX.Y.Z]\n' "$0" >&2
  exit 1
}

ensure_mac_dirs
require_cmd jq
require_cmd python3

pob_tag="$(resolve_pob_tag "${1:-latest}")"
[[ -n "$pob_tag" ]] || usage

log "Resolving official Path of Building release ${pob_tag}"
pob_repo="$(game_repo)"
pob_release_json="$(github_api "https://api.github.com/repos/${pob_repo}/releases/tags/${pob_tag}")"
pob_version="$(printf '%s' "$pob_release_json" | jq -r '.tag_name | ltrimstr("v")')"
pob_published_at="$(printf '%s' "$pob_release_json" | jq -r '.published_at')"

download_compatibility_file
minimum_rusty="$(minimum_rusty_version_for_pob "$pob_version" "$(compat_file_path)")"
rusty_tag="$(resolve_rusty_tag "$minimum_rusty")"

log "Resolved runtime mapping: PoB ${pob_tag} -> Rusty ${rusty_tag} (minimum ${minimum_rusty})"
rusty_release_json="$(github_api "https://api.github.com/repos/${POB_MAC_RUSTY_REPO}/releases/tags/${rusty_tag}")"
rusty_version="$(printf '%s' "$rusty_release_json" | jq -r '.tag_name | ltrimstr("v")')"
rusty_published_at="$(printf '%s' "$rusty_release_json" | jq -r '.published_at')"

extract_github_tarball "$pob_repo" "$pob_tag" "${UPSTREAM_ROOT}/pob/${pob_tag}"
extract_github_tarball "$POB_MAC_RUSTY_REPO" "$rusty_tag" "${UPSTREAM_ROOT}/rusty/${rusty_tag}"

write_version_metadata \
  "$pob_tag" \
  "$pob_version" \
  "$pob_published_at" \
  "$rusty_tag" \
  "$rusty_version" \
  "$rusty_published_at" \
  "$minimum_rusty"

log "Updated native metadata: ${VERSION_METADATA_FILE}"
