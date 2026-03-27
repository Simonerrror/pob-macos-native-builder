#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

usage() {
  printf 'Usage: %s [latest|<flathub-commit>]\n' "$0" >&2
  exit 1
}

resolve_snapshot() {
  local raw="${1:-latest}"
  if [[ "$raw" == "latest" ]]; then
    latest_upstream_snapshot
  elif [[ "$raw" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "$raw"
  else
    usage
  fi
}

insert_build_mount() {
  local source_path="$1"
  local target_path="$2"

  awk '
    BEGIN {
      in_finish=0
      has_mount=0
      inserted=0
    }
    /^finish-args:$/ {
      in_finish=1
      print
      next
    }
    in_finish && /^  - --filesystem=\/data\/builds$/ {
      has_mount=1
      print
      next
    }
    in_finish && /^[^ ]/ {
      if (!has_mount && !inserted) {
        print "  - --filesystem=/data/builds"
        inserted=1
      }
      in_finish=0
      print
      next
    }
    {
      print
    }
    END {
      if (in_finish && !has_mount && !inserted) {
        print "  - --filesystem=/data/builds"
      }
    }
  ' "$source_path" > "$target_path"
}

ensure_flatpak_dirs

snapshot="$(resolve_snapshot "${1:-latest}")"
manifest_url="https://raw.githubusercontent.com/flathub/community.pathofbuilding.PathOfBuilding/${snapshot}/community.pathofbuilding.PathOfBuilding.yml"

log "Syncing upstream snapshot ${snapshot}"
curl -fL --retry 3 --retry-delay 2 -o "$FLATPAK_UPSTREAM_MANIFEST_PATH" "$manifest_url"
download_cargo_sources "$snapshot" refresh
stage_manifest_cargo_sources

tmp_manifest="$(mktemp)"
tmp_filtered="$(mktemp)"
trap 'rm -f "$tmp_manifest" "$tmp_filtered"' EXIT

awk '
  /^  - name: extrafiles$/ { exit }
  { print }
' "$FLATPAK_UPSTREAM_MANIFEST_PATH" > "$tmp_manifest"

insert_build_mount "$tmp_manifest" "$tmp_filtered"

awk '
  /^      - install -Dm0644 cargo\/config \.cargo\/config\.toml$/ {
    print "      - mkdir -p .cargo && if [ -f cargo/config ]; then install -Dm0644 cargo/config .cargo/config.toml; elif [ -f cargo/config.toml ]; then install -Dm0644 cargo/config.toml .cargo/config.toml; fi"
    next
  }
  { print }
' "$tmp_filtered" > "$FLATPAK_MANIFEST"

printf '%s\n' "$snapshot" > "$UPSTREAM_HEAD_FILE"

log "Updated local manifest: ${FLATPAK_MANIFEST}"
log "Updated cargo-sources cache: ${FLATPAK_CARGO_SOURCES_PATH}"
