#!/usr/bin/env bash
set -euo pipefail

refresh=""
if [[ "${1:-}" == "--refresh" ]]; then
  refresh="refresh"
elif [[ $# -gt 0 ]]; then
  printf 'Usage: %s [--refresh]\n' "$0" >&2
  exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

ensure_flatpak_dirs
ensure_manifest_exists
download_cargo_sources "${FLATPAK_UPSTREAM_SNAPSHOT}" "$refresh"
stage_manifest_cargo_sources
build_flatpak_image

runtime_version="$(manifest_runtime_version)"

run_in_flatpak_image "
  set -euo pipefail
  flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y --noninteractive flathub \
    org.freedesktop.Platform//${runtime_version} \
    org.freedesktop.Sdk//${runtime_version} \
    org.freedesktop.Sdk.Extension.rust-stable//${runtime_version}
"

log "Bootstrap complete"
