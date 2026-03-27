#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/flatpak-common.sh"

usage() {
  printf 'Usage: %s [--no-open]\n' "$0" >&2
  exit 1
}

open_windows_app=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-open)
      open_windows_app=0
      ;;
    *)
      usage
      ;;
  esac
  shift
done

RDP_DIR="${APP_STATE_ROOT}/rdp"
RDP_FILE="${RDP_DIR}/POB.rdp"
RDP_HOST="${POB_RDP_HOST:-localhost}"
RDP_PORT="${POB_FLATPAK_RDP_PORT:-${POB_RDP_PORT:-3389}}"
RDP_USER="${POB_RDP_USERNAME:-root}"
CONTAINER_NAME="${POB_RDP_CONTAINER_NAME:-pob-flatpak-rdp}"
WAIT_TIMEOUT="${POB_RDP_WAIT_TIMEOUT:-60}"

ensure_rdp_file() {
  mkdir -p "$RDP_DIR"
  cat >"$RDP_FILE" <<EOF
full address:s:${RDP_HOST}:${RDP_PORT}
username:s:${RDP_USER}
prompt for credentials on client:i:1
authentication level:i:2
negotiate security layer:i:1
redirectclipboard:i:1
drivestoredirect:s:
screen mode id:i:1
use multimon:i:0
session bpp:i:32
desktopwidth:i:1470
desktopheight:i:923
EOF
}

wait_for_runner() {
  local started_at
  started_at="$(date +%s)"
  while true; do
    if docker_cmd inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null | grep -q '^healthy$'; then
      return 0
    fi
    if (( "$(date +%s)" - started_at >= WAIT_TIMEOUT )); then
      printf 'Timed out waiting for %s to become healthy.\n' "$CONTAINER_NAME" >&2
      exit 1
    fi
    sleep 1
  done
}

ensure_rdp_file
"${REPO_ROOT}/scripts/up.sh"
wait_for_runner

if [[ "$open_windows_app" -eq 1 ]]; then
  open -a "Windows App" "$RDP_FILE"
else
  printf 'Runner is healthy. RDP file: %s\n' "$RDP_FILE"
fi
