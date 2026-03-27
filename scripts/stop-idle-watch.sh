#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

if [[ ! -f "$IDLE_WATCH_PID_FILE" ]]; then
  exit 0
fi

watch_pid="$(cat "$IDLE_WATCH_PID_FILE" 2>/dev/null || true)"
if [[ -z "$watch_pid" ]]; then
  rm -f "$IDLE_WATCH_PID_FILE"
  exit 0
fi

if [[ -n "${POB_IDLE_WATCH_SELF_PID:-}" && "$watch_pid" == "$POB_IDLE_WATCH_SELF_PID" ]]; then
  rm -f "$IDLE_WATCH_PID_FILE"
  exit 0
fi

if kill -0 "$watch_pid" 2>/dev/null; then
  kill "$watch_pid" 2>/dev/null || true
fi

rm -f "$IDLE_WATCH_PID_FILE"
