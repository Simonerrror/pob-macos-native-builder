#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${RUNTIME_DIR:-/runtime}"
BUILD_DIR="${BUILD_DIR:-/data/builds}"
WINEPREFIX="${WINEPREFIX:-/wine-prefix}"
LOG_DIR="${LOG_DIR:-/var/log/pob}"
POB_EXE_FILE="${POB_EXE_FILE:-/run/pob-exe}"

mkdir -p "$LOG_DIR" "$BUILD_DIR" "$WINEPREFIX"

export WINEPREFIX
export WINEDEBUG="${WINEDEBUG:--all}"
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"

fluxbox -log "$LOG_DIR/fluxbox.log" >>"$LOG_DIR/fluxbox.stdout" 2>&1 &
FLUXBOX_PID=$!

# Give the window manager a moment to own the root window before Wine creates windows.
sleep 1

if [[ -s "$POB_EXE_FILE" ]]; then
  POB_EXE="$(cat "$POB_EXE_FILE")"
elif [[ -d "$RUNTIME_DIR" ]]; then
  POB_EXE="$(find "$RUNTIME_DIR" -maxdepth 4 -type f \( -iname 'Path of Building*.exe' -o -iname 'PathOfBuilding*.exe' \) ! -iname '*setup*.exe' | sort | head -n 1 || true)"
else
  POB_EXE=""
fi

if [[ -z "${POB_EXE:-}" || ! -f "${POB_EXE:-}" ]]; then
  printf '[pob-session] PoB executable not found\n' >>"$LOG_DIR/pob.log"
else
  printf '[pob-session] Launching %s\n' "$POB_EXE" >>"$LOG_DIR/pob.log"
  wine "$POB_EXE" >>"$LOG_DIR/pob.log" 2>&1 &
fi

wait "$FLUXBOX_PID"
