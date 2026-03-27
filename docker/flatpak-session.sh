#!/usr/bin/env bash
set -euo pipefail

APP_ID="${POB_FLATPAK_APP_ID:-community.pathofbuilding.PathOfBuilding}"
BUILD_DIR="${BUILD_DIR:-/data/builds}"
LOG_DIR="${LOG_DIR:-/var/log/pob-flatpak}"
HOME="${HOME:-/root}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
APP_VAR_DIR="${HOME}/.var/app/${APP_ID}"
GAME_TARGET="${POB_FLATPAK_GAME:-poe1}"

mkdir -p "$LOG_DIR" "$BUILD_DIR" "$XDG_RUNTIME_DIR" "${APP_VAR_DIR}/data" "${APP_VAR_DIR}/config"
chmod 0700 "$XDG_RUNTIME_DIR"

export HOME
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

link_build_dir() {
  local root="$1"
  local app_dir
  mkdir -p "$root"
  for app_dir in \
    "Path of Building" \
    "Path of Building Community" \
    "RustyPathOfBuilding1" \
    "RustyPathOfBuilding2"; do
    mkdir -p "$root/$app_dir"
    rm -rf "$root/$app_dir/Builds"
    ln -sfn "$BUILD_DIR" "$root/$app_dir/Builds"
  done
}

link_build_dir "${APP_VAR_DIR}/data"
link_build_dir "${APP_VAR_DIR}/config"

dbus-run-session -- bash -lc '
  set -euo pipefail
  export HOME="'"$HOME"'"
  export LANG="'"${LANG:-C.UTF-8}"'"
  export LC_ALL="'"${LC_ALL:-C.UTF-8}"'"
  export XDG_RUNTIME_DIR="'"$XDG_RUNTIME_DIR"'"
  export XDG_SESSION_TYPE="'"${XDG_SESSION_TYPE:-x11}"'"
  fluxbox -log "'"$LOG_DIR"'/fluxbox.log" >>"'"$LOG_DIR"'/fluxbox.stdout" 2>&1 &
  FLUXBOX_PID=$!
  sleep 1
  flatpak run "'"$APP_ID"'" "'"$GAME_TARGET"'" >>"'"$LOG_DIR"'/app.log" 2>&1 &
  wait "$FLUXBOX_PID"
'
