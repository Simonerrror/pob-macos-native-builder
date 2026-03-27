#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

LOCK_DIR="${APP_STATE_ROOT}/flatpak-refresh.lock"
force=0
restart=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    --no-restart)
      restart=0
      ;;
    *)
      printf 'Usage: %s [--force] [--no-restart]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

ensure_flatpak_dirs

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another flatpak refresh is already in progress; skipping."
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

latest_snapshot="$(latest_upstream_snapshot)"
current_snapshot=""
if [[ -s "$UPSTREAM_HEAD_FILE" ]]; then
  current_snapshot="$(<"$UPSTREAM_HEAD_FILE")"
fi

if [[ "$force" -eq 0 && -n "$current_snapshot" && "$current_snapshot" == "$latest_snapshot" ]]; then
  log "No upstream changes detected; snapshot ${latest_snapshot} is already applied."
  printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" > "$LAST_REFRESH_FILE"
  exit 0
fi

log "Refreshing upstream manifest from ${latest_snapshot}"
"${REPO_ROOT}/scripts/flatpak-sync-upstream.sh" "$latest_snapshot"
"${REPO_ROOT}/scripts/flatpak-build.sh"

if [[ "$restart" -eq 1 ]]; then
  log "Recreating flatpak runner"
  "${REPO_ROOT}/scripts/up.sh"
fi

printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" > "$LAST_REFRESH_FILE"
log "Flatpak refresh complete"
