#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_ROOT="${REPO_ROOT}/.state"
LOCK_DIR="${STATE_ROOT}/prefetch.lock"

log() {
  printf '[prefetch-latest] %s\n' "$*"
}

mkdir -p "$STATE_ROOT"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another prefetch run is already in progress; skipping."
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR"
}

trap cleanup EXIT

exec "${REPO_ROOT}/scripts/sync-release.sh" --prefetch latest
