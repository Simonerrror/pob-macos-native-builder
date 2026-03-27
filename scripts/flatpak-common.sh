#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/.cache/flatpak"
UPSTREAM_DIR="${CACHE_ROOT}/upstream"
BUILD_DIR="${CACHE_ROOT}/build/app"
REPO_DIR="${CACHE_ROOT}/repo"
STATE_ROOT="${CACHE_ROOT}/state"
SYSTEM_STATE_DIR="${STATE_ROOT}/system"
HOME_STATE_DIR="${STATE_ROOT}/home"
BUILDER_STATE_DIR="${STATE_ROOT}/builder"
LOG_DIR="${STATE_ROOT}/logs"
DOCKER_CONTEXT_ARG=()
FLATPAK_IMAGE="${POB_FLATPAK_IMAGE:-pob-flatpak:local}"
FLATPAK_APP_ID="${POB_FLATPAK_APP_ID:-community.pathofbuilding.PathOfBuilding}"
FLATPAK_REMOTE="${POB_FLATPAK_LOCAL_REMOTE:-localrepo}"
FLATPAK_RUNTIME_VERSION="${POB_FLATPAK_RUNTIME_VERSION:-25.08}"
FLATPAK_UPSTREAM_SNAPSHOT="${POB_FLATPAK_UPSTREAM_SNAPSHOT:-aa186a1606107b3f9035ea03d72c79e8ea24c885}"
FLATPAK_CARGO_SOURCES_URL="https://raw.githubusercontent.com/flathub/community.pathofbuilding.PathOfBuilding/${FLATPAK_UPSTREAM_SNAPSHOT}/cargo-sources.json"
FLATPAK_CARGO_SOURCES_PATH="${UPSTREAM_DIR}/cargo-sources.json"
FLATPAK_MANIFEST="${REPO_ROOT}/flatpak/community.pathofbuilding.PathOfBuilding.yml"
DEFAULT_BUILD_DIR="/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds"

if [[ -n "${POB_DOCKER_CONTEXT:-}" ]]; then
  DOCKER_CONTEXT_ARG=(--context "$POB_DOCKER_CONTEXT")
elif docker context inspect orbstack >/dev/null 2>&1; then
  DOCKER_CONTEXT_ARG=(--context orbstack)
fi

log() {
  printf '[flatpak-common] %s\n' "$*"
}

docker_cmd() {
  docker "${DOCKER_CONTEXT_ARG[@]}" "$@"
}

ensure_flatpak_dirs() {
  mkdir -p "$UPSTREAM_DIR" "$BUILD_DIR" "$REPO_DIR" "$SYSTEM_STATE_DIR" "$HOME_STATE_DIR" "$BUILDER_STATE_DIR" "$LOG_DIR"
  mkdir -p "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}"
}

ensure_manifest_exists() {
  if [[ ! -f "$FLATPAK_MANIFEST" ]]; then
    printf 'Flatpak manifest not found at %s\n' "$FLATPAK_MANIFEST" >&2
    exit 1
  fi
}

download_cargo_sources() {
  local refresh="${1:-}"
  if [[ "$refresh" == "refresh" || ! -s "$FLATPAK_CARGO_SOURCES_PATH" ]]; then
    log "Downloading cargo-sources.json from snapshot ${FLATPAK_UPSTREAM_SNAPSHOT}"
    curl -fL --retry 3 --retry-delay 2 -o "$FLATPAK_CARGO_SOURCES_PATH" "$FLATPAK_CARGO_SOURCES_URL"
  fi
}

build_flatpak_image() {
  log "Building flatpak helper image: ${FLATPAK_IMAGE}"
  docker_cmd build -f "${REPO_ROOT}/Dockerfile.flatpak" -t "$FLATPAK_IMAGE" "$REPO_ROOT"
}

run_in_flatpak_image() {
  local cmd="$1"
  docker_cmd run --rm --privileged \
    --entrypoint bash \
    -v "${REPO_ROOT}:/workspace" \
    -v "${SYSTEM_STATE_DIR}:/var/lib/flatpak" \
    -v "${HOME_STATE_DIR}:/root" \
    -v "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}:/data/builds" \
    -w /workspace \
    "$FLATPAK_IMAGE" \
    -lc "$cmd"
}
