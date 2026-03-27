#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

ensure_flatpak_dirs
ensure_manifest_exists
"${REPO_ROOT}/scripts/flatpak-bootstrap.sh"

run_in_flatpak_image "
  set -euo pipefail
  flatpak-builder \
    --disable-rofiles-fuse \
    --force-clean \
    --repo=/workspace/.cache/flatpak/repo \
    --state-dir=/workspace/.cache/flatpak/state/builder \
    /workspace/.cache/flatpak/build/app \
    /workspace/flatpak/community.pathofbuilding.PathOfBuilding.yml
  flatpak build-update-repo /workspace/.cache/flatpak/repo
"

log "Build complete for ${FLATPAK_APP_ID}"
