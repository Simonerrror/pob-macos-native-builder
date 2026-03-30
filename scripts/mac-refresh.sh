#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    *)
      printf 'Usage: %s [--force]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

ensure_mac_dirs

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another mac-native refresh is already in progress; skipping."
  exit 0
fi

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

latest_tag="$(latest_pob_tag)"
current_tag=""
if [[ -f "$VERSION_METADATA_FILE" ]]; then
  current_tag="$(metadata_value '.pob.tag')"
fi

if [[ "$force" -eq 0 && -n "$current_tag" && "$current_tag" == "$latest_tag" && -d "$POB_MAC_BUNDLE_PATH" ]]; then
  log "No upstream changes detected; native bundle already tracks ${latest_tag}."
  printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" > "$LAST_REFRESH_FILE"
  exit 0
fi

"${REPO_ROOT}/scripts/mac-sync-upstream.sh" "$latest_tag"
"${REPO_ROOT}/scripts/mac-build.sh"
"${REPO_ROOT}/scripts/mac-bundle.sh"
"${REPO_ROOT}/scripts/mac-smoke-test.sh"

printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" > "$LAST_REFRESH_FILE"
log "Mac-native refresh complete"
