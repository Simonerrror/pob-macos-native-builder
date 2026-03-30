#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

open_app=1
force_refresh=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-open)
      open_app=0
      ;;
    --rebuild)
      force_refresh=1
      ;;
    *)
      printf 'Usage: %s [--no-open] [--rebuild]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

ensure_mac_dirs

if [[ "$force_refresh" -eq 1 || ! -d "$POB_MAC_BUNDLE_PATH" ]]; then
  "${REPO_ROOT}/scripts/mac-refresh.sh" --force
fi

if [[ "$open_app" -eq 1 ]]; then
  open "$POB_MAC_BUNDLE_PATH"
else
  printf 'Native app ready: %s\n' "$POB_MAC_BUNDLE_PATH"
fi
