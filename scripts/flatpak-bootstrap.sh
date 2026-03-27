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
download_cargo_sources "$refresh"
build_flatpak_image

run_in_flatpak_image "
  set -euo pipefail
  flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y --noninteractive flathub \
    org.freedesktop.Platform//${FLATPAK_RUNTIME_VERSION} \
    org.freedesktop.Sdk//${FLATPAK_RUNTIME_VERSION} \
    org.freedesktop.Sdk.Extension.rust-stable//${FLATPAK_RUNTIME_VERSION}
"

log "Bootstrap complete"
