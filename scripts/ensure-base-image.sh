#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${REPO_ROOT}/.cache/images"
DOCKER_CONTEXT_ARG=()
IMAGE_REF="${POB_BASE_IMAGE:-debian:bookworm-slim}"

if [[ -n "${POB_DOCKER_CONTEXT:-}" ]]; then
  DOCKER_CONTEXT_ARG=(--context "$POB_DOCKER_CONTEXT")
elif docker context inspect orbstack >/dev/null 2>&1; then
  DOCKER_CONTEXT_ARG=(--context orbstack)
fi

mkdir -p "$CACHE_DIR"

safe_name="$(printf '%s' "$IMAGE_REF" | tr '/:' '--')"
archive_path="${CACHE_DIR}/${safe_name}.tar"

log() {
  printf '[ensure-base-image] %s\n' "$*"
}

docker_cmd() {
  docker "${DOCKER_CONTEXT_ARG[@]}" "$@"
}

if docker_cmd image inspect "$IMAGE_REF" >/dev/null 2>&1; then
  log "Image already present locally: ${IMAGE_REF}"
elif [[ -f "$archive_path" ]]; then
  log "Loading cached image archive: ${archive_path}"
  docker_cmd load -i "$archive_path" >/dev/null
else
  log "Pulling image from registry: ${IMAGE_REF}"
  docker_cmd pull "$IMAGE_REF"
fi

if [[ ! -f "$archive_path" ]]; then
  log "Saving image archive: ${archive_path}"
  docker_cmd save -o "$archive_path" "$IMAGE_REF"
fi

log "Ready: ${IMAGE_REF}"

