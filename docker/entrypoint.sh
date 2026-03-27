#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/data/builds}"
POB_RDP_PORT="${POB_RDP_PORT:-3389}"
POB_RDP_PASSWORD="${POB_RDP_PASSWORD:-}"
WINEPREFIX="${WINEPREFIX:-/wine-prefix}"
RUNTIME_DIR="/runtime"
LOG_DIR="/var/log/pob"
POB_EXE_FILE="/run/pob-exe"
WINE_USER_DIR="${WINEPREFIX}/drive_c/users/$(id -un)"

pids=()

log() {
  printf '[pob-entrypoint] %s\n' "$*"
}

cleanup() {
  local status=$?
  set +e
  for pid in "${pids[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  wait || true
  exit "$status"
}
trap cleanup EXIT INT TERM

require_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    log "$label is missing: $path"
    exit 1
  fi
}

ensure_wine_prefix() {
  mkdir -p "$WINEPREFIX" "$BUILD_DIR" "$LOG_DIR"
  if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    log "Initializing wine prefix at $WINEPREFIX"
    wineboot -u >"$LOG_DIR/wineboot.log" 2>&1
  fi
}

link_build_dir() {
  local docs_root="$1"
  local app_dir
  mkdir -p "$docs_root"
  for app_dir in "Path of Building" "Path of Building Community"; do
    mkdir -p "$docs_root/$app_dir"
    rm -rf "$docs_root/$app_dir/Builds"
    ln -sfn "$BUILD_DIR" "$docs_root/$app_dir/Builds"
  done
}

bootstrap_user_paths() {
  mkdir -p "$WINE_USER_DIR"
  link_build_dir "$WINE_USER_DIR/Documents"
  link_build_dir "$WINE_USER_DIR/My Documents"
}

find_pob_exe() {
  local exe
  exe="$(find "$RUNTIME_DIR" -maxdepth 4 -type f \( -iname 'Path of Building*.exe' -o -iname 'PathOfBuilding*.exe' \) ! -iname '*setup*.exe' | sort | head -n 1 || true)"
  if [[ -z "$exe" ]]; then
    exe="$(find "$RUNTIME_DIR" -maxdepth 4 -type f -iname '*.exe' ! -iname '*setup*.exe' | sort | head -n 1 || true)"
  fi
  if [[ -z "$exe" ]]; then
    log "Could not locate a PoB executable under $RUNTIME_DIR"
    exit 1
  fi
  printf '%s\n' "$exe"
}

configure_root_password() {
  if [[ -z "$POB_RDP_PASSWORD" ]]; then
    log "POB_RDP_PASSWORD is required for xrdp login"
    exit 1
  fi
  printf 'root:%s\n' "$POB_RDP_PASSWORD" | chpasswd
}

configure_xrdp() {
  awk -v port="$POB_RDP_PORT" '
    /^\[Globals\]/ { in_globals=1; print; next }
    /^\[/ && $0 != "[Globals]" { in_globals=0; print; next }
    in_globals && /^port=/ { print "port=" port; next }
    { print }
  ' /etc/xrdp/xrdp.ini > /etc/xrdp/xrdp.ini.tmp
  mv /etc/xrdp/xrdp.ini.tmp /etc/xrdp/xrdp.ini
  mkdir -p /var/run/dbus /run/xrdp
  cat > /etc/xrdp/startwm.sh <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/pob-session
EOF
  chmod +x /etc/xrdp/startwm.sh
  printf '%s\n' "$(find_pob_exe)" >"$POB_EXE_FILE"
}

start_sesman() {
  log "Starting xrdp-sesman"
  /usr/sbin/xrdp-sesman --nodaemon >"$LOG_DIR/xrdp-sesman.log" 2>&1 &
  pids+=("$!")
}

require_dir "$RUNTIME_DIR" "Mounted runtime directory"
require_dir "$BUILD_DIR" "Mounted build directory"
require_dir "$WINEPREFIX" "Mounted wine prefix directory"

mkdir -p "$LOG_DIR"
ensure_wine_prefix
bootstrap_user_paths
configure_root_password
configure_xrdp
start_sesman
log "Starting xrdp on port $POB_RDP_PORT"
exec /usr/sbin/xrdp --nodaemon >"$LOG_DIR/xrdp.log" 2>&1
