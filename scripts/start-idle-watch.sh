#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

if [[ "${POB_IDLE_AUTO_DOWN:-1}" != "1" ]]; then
  exit 0
fi

ensure_flatpak_dirs
mkdir -p "$(dirname "$IDLE_WATCH_LOG_FILE")"

if [[ -f "$IDLE_WATCH_PID_FILE" ]]; then
  existing_pid="$(cat "$IDLE_WATCH_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    printf 'Idle watcher already running: %s\n' "$existing_pid"
    exit 0
  fi
  rm -f "$IDLE_WATCH_PID_FILE"
fi

nohup "${REPO_ROOT}/scripts/pob-idle-watch.sh" >>"$IDLE_WATCH_LOG_FILE" 2>&1 &
watch_pid="$!"
disown "$watch_pid" 2>/dev/null || true
printf '%s\n' "$watch_pid" >"$IDLE_WATCH_PID_FILE"
printf 'Started idle watcher: %s\n' "$watch_pid"
