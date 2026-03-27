#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

mode="${1:-builder}"
case "$mode" in
  builder|runner)
    ;;
  *)
    printf 'Usage: %s [builder|runner]\n' "$0" >&2
    exit 1
    ;;
esac

ensure_flatpak_dirs
if [[ "$mode" == "builder" ]]; then
  build_flatpak_builder_image
  exec docker "${DOCKER_CONTEXT_ARG[@]}" run --rm -it --privileged \
    --entrypoint bash \
    -v "${REPO_ROOT}:/workspace" \
    -v "${SYSTEM_STATE_DIR}:/var/lib/flatpak" \
    -v "${HOME_STATE_DIR}:/root" \
    -v "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}:/data/builds" \
    -w /workspace \
    "$FLATPAK_BUILDER_IMAGE"
fi

build_flatpak_runner_image
exec docker "${DOCKER_CONTEXT_ARG[@]}" run --rm -it --privileged \
  --entrypoint bash \
  -v "${REPO_DIR}:/repo:ro" \
  -v "${SYSTEM_STATE_DIR}:/var/lib/flatpak" \
  -v "${HOME_STATE_DIR}:/root" \
  -v "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}:/data/builds" \
  "$FLATPAK_RUNNER_IMAGE"
