#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

ensure_flatpak_dirs
build_flatpak_image

exec docker "${DOCKER_CONTEXT_ARG[@]}" run --rm -it --privileged \
  --entrypoint bash \
  -v "${REPO_ROOT}:/workspace" \
  -v "${SYSTEM_STATE_DIR}:/var/lib/flatpak" \
  -v "${HOME_STATE_DIR}:/root" \
  -v "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}:/data/builds" \
  -w /workspace \
  "$FLATPAK_IMAGE"
