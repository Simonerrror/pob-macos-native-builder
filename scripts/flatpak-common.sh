#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/.cache/flatpak"
UPSTREAM_DIR="${CACHE_ROOT}/upstream"
BUILD_DIR="${CACHE_ROOT}/build/app"
REPO_DIR="${CACHE_ROOT}/repo"
FLATPAK_STATE_ROOT="${CACHE_ROOT}/state"
SYSTEM_STATE_DIR="${FLATPAK_STATE_ROOT}/system"
HOME_STATE_DIR="${FLATPAK_STATE_ROOT}/home"
BUILDER_STATE_DIR="${FLATPAK_STATE_ROOT}/builder"
LOG_DIR="${FLATPAK_STATE_ROOT}/logs"
APP_STATE_ROOT="${REPO_ROOT}/.state"
UPSTREAM_HEAD_FILE="${APP_STATE_ROOT}/flatpak-upstream-head"
LAST_REFRESH_FILE="${APP_STATE_ROOT}/flatpak-upstream-last-refresh"
DOCKER_CONTEXT_ARG=()
FLATPAK_IMAGE="${POB_FLATPAK_IMAGE:-pob-flatpak:local}"
FLATPAK_APP_ID="${POB_FLATPAK_APP_ID:-community.pathofbuilding.PathOfBuilding}"
FLATPAK_REMOTE="${POB_FLATPAK_LOCAL_REMOTE:-localrepo}"
FLATPAK_GAME="${POB_FLATPAK_GAME:-poe1}"
FLATPAK_UPSTREAM_SNAPSHOT="${POB_FLATPAK_UPSTREAM_SNAPSHOT:-aa186a1606107b3f9035ea03d72c79e8ea24c885}"
FLATPAK_CARGO_SOURCES_URL="https://raw.githubusercontent.com/flathub/community.pathofbuilding.PathOfBuilding/${FLATPAK_UPSTREAM_SNAPSHOT}/cargo-sources.json"
FLATPAK_CARGO_SOURCES_PATH="${UPSTREAM_DIR}/cargo-sources.json"
FLATPAK_UPSTREAM_MANIFEST_PATH="${UPSTREAM_DIR}/community.pathofbuilding.PathOfBuilding.yml"
FLATPAK_MANIFEST="${REPO_ROOT}/flatpak/community.pathofbuilding.PathOfBuilding.yml"
FLATPAK_MANIFEST_CARGO_SOURCES_PATH="${REPO_ROOT}/flatpak/cargo-sources.json"
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
  mkdir -p "$UPSTREAM_DIR" "$BUILD_DIR" "$REPO_DIR" "$SYSTEM_STATE_DIR" "$HOME_STATE_DIR" "$BUILDER_STATE_DIR" "$LOG_DIR" "$APP_STATE_ROOT"
  mkdir -p "${POB_BUILDS_HOST_DIR:-$DEFAULT_BUILD_DIR}"
}

ensure_manifest_exists() {
  if [[ ! -f "$FLATPAK_MANIFEST" ]]; then
    printf 'Flatpak manifest not found at %s\n' "$FLATPAK_MANIFEST" >&2
    exit 1
  fi
}

manifest_runtime_version() {
  local runtime_version
  runtime_version="$(sed -nE "s/^runtime-version: '?([^']+)'?$/\\1/p" "$FLATPAK_MANIFEST" | head -n1)"
  if [[ -n "$runtime_version" ]]; then
    printf '%s\n' "$runtime_version"
  else
    printf '%s\n' "${POB_FLATPAK_RUNTIME_VERSION:-25.08}"
  fi
}

latest_upstream_snapshot() {
  git ls-remote https://github.com/flathub/community.pathofbuilding.PathOfBuilding.git HEAD | awk '{print $1}'
}

download_cargo_sources() {
  local snapshot="${1:-$FLATPAK_UPSTREAM_SNAPSHOT}"
  local refresh="${2:-}"
  local url="https://raw.githubusercontent.com/flathub/community.pathofbuilding.PathOfBuilding/${snapshot}/cargo-sources.json"
  if [[ "$refresh" == "refresh" || ! -s "$FLATPAK_CARGO_SOURCES_PATH" ]]; then
    log "Downloading cargo-sources.json from snapshot ${snapshot}"
    curl -fL --retry 3 --retry-delay 2 -o "$FLATPAK_CARGO_SOURCES_PATH" "$url"
  fi
}

stage_manifest_cargo_sources() {
  if [[ ! -s "$FLATPAK_CARGO_SOURCES_PATH" ]]; then
    printf 'Missing cached cargo-sources file at %s\n' "$FLATPAK_CARGO_SOURCES_PATH" >&2
    exit 1
  fi
  cp "$FLATPAK_CARGO_SOURCES_PATH" "$FLATPAK_MANIFEST_CARGO_SOURCES_PATH"
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
