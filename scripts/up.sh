#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_LINK="${REPO_ROOT}/.cache/runtime/current"
DEFAULT_BUILD_DIR="/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds"
DEFAULT_WINE_DIR="/Users/sergio/Documents/30_HOBBY_AI/POB-data/wine-prefix"
DOCKER_CONTEXT_ARG=()

if [[ -n "${POB_DOCKER_CONTEXT:-}" ]]; then
  DOCKER_CONTEXT_ARG=(--context "$POB_DOCKER_CONTEXT")
elif docker context inspect orbstack >/dev/null 2>&1; then
  DOCKER_CONTEXT_ARG=(--context orbstack)
fi

if [[ ! -d "$RUNTIME_LINK" ]]; then
  printf 'Runtime not found at %s\nRun ./scripts/sync-release.sh latest first.\n' "$RUNTIME_LINK" >&2
  exit 1
fi

mkdir -p "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}" "${POB_WINEPREFIX_HOST_DIR:-$DEFAULT_WINE_DIR}"
"${REPO_ROOT}/scripts/ensure-base-image.sh"
exec docker "${DOCKER_CONTEXT_ARG[@]}" compose -f "${REPO_ROOT}/docker-compose.yml" up -d "$@"
