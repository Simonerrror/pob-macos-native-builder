#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

ensure_flatpak_dirs
build_flatpak_runner_image

if [[ ! -f "${REPO_DIR}/config" ]]; then
  printf 'Flatpak repo not found at %s\nRun ./scripts/flatpak-build.sh first.\n' "$REPO_DIR" >&2
  exit 1
fi

export POB_FLATPAK_RUNNER_IMAGE="$FLATPAK_RUNNER_IMAGE"
export POB_FLATPAK_RDP_PORT="${POB_FLATPAK_RDP_PORT:-${POB_RDP_PORT:-3389}}"
exec docker "${DOCKER_CONTEXT_ARG[@]}" compose -f "${REPO_ROOT}/docker-compose.flatpak.yml" up -d --build "$@"
