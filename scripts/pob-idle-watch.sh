#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

RDP_PORT="${POB_FLATPAK_RDP_PORT:-${POB_RDP_PORT:-3389}}"
CONTAINER_NAME="${POB_RDP_CONTAINER_NAME:-pob-flatpak-rdp}"
TIMEOUT_MINUTES="${POB_IDLE_TIMEOUT_MINUTES:-20}"
POLL_SECONDS="${POB_IDLE_POLL_SECONDS:-60}"
TIMEOUT_SECONDS="$(( TIMEOUT_MINUTES * 60 ))"

log_watch() {
  printf '[pob-idle-watch] %s\n' "$*"
}

cleanup() {
  if [[ -f "$IDLE_WATCH_PID_FILE" ]] && [[ "$(cat "$IDLE_WATCH_PID_FILE" 2>/dev/null)" == "$$" ]]; then
    rm -f "$IDLE_WATCH_PID_FILE"
  fi
}
trap cleanup EXIT INT TERM

container_running() {
  docker_cmd inspect "$CONTAINER_NAME" --format '{{.State.Running}}' 2>/dev/null | grep -q '^true$'
}

has_active_rdp_client() {
  lsof -nP -iTCP:"$RDP_PORT" -sTCP:ESTABLISHED -Fp 2>/dev/null | grep -q '^p'
}

last_active_at="$(date +%s)"
log_watch "Watching localhost:${RDP_PORT}; timeout=${TIMEOUT_MINUTES}m poll=${POLL_SECONDS}s"

while true; do
  if ! container_running; then
    log_watch "Container ${CONTAINER_NAME} is no longer running; exiting watcher"
    exit 0
  fi

  if has_active_rdp_client; then
    last_active_at="$(date +%s)"
  else
    now="$(date +%s)"
    if (( now - last_active_at >= TIMEOUT_SECONDS )); then
      log_watch "No active RDP client for ${TIMEOUT_MINUTES} minutes; stopping ${CONTAINER_NAME}"
      POB_IDLE_WATCH_SELF_PID="$$" "${REPO_ROOT}/scripts/down.sh"
      exit 0
    fi
  fi

  sleep "$POLL_SECONDS"
done
