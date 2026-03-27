#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/data/builds}"
POB_RDP_PORT="${POB_RDP_PORT:-3389}"
POB_RDP_PASSWORD="${POB_RDP_PASSWORD:-}"
POB_RDP_KEYLAYOUT="${POB_RDP_KEYLAYOUT:-0x00000409}"
POB_FLATPAK_APP_ID="${POB_FLATPAK_APP_ID:-community.pathofbuilding.PathOfBuilding}"
POB_FLATPAK_LOCAL_REMOTE="${POB_FLATPAK_LOCAL_REMOTE:-localrepo}"
POB_FLATPAK_REPO_DIR="${POB_FLATPAK_REPO_DIR:-/repo}"
POB_RDP_CERT_FILE="${POB_RDP_CERT_FILE:-/tls/server.crt}"
POB_RDP_KEY_FILE="${POB_RDP_KEY_FILE:-/tls/server.key}"
LOG_DIR="/var/log/pob-flatpak"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"

pids=()

log() {
  printf '[pob-flatpak-entrypoint] %s\n' "$*"
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

configure_root_password() {
  if [[ -z "$POB_RDP_PASSWORD" ]]; then
    log "POB_RDP_PASSWORD is required for xrdp login"
    exit 1
  fi
  printf 'root:%s\n' "$POB_RDP_PASSWORD" | chpasswd
}

prepare_runtime_dirs() {
  mkdir -p "$LOG_DIR" "$BUILD_DIR" "$XDG_RUNTIME_DIR" /var/run/dbus /run/xrdp /var/lib/flatpak /root
  chmod 0700 "$XDG_RUNTIME_DIR"
}

configure_xrdp() {
  awk -v port="$POB_RDP_PORT" -v keylayout="$POB_RDP_KEYLAYOUT" -v cert="$POB_RDP_CERT_FILE" -v key="$POB_RDP_KEY_FILE" '
    /^\[Globals\]/ { in_globals=1; print; next }
    /^\[/ && $0 != "[Globals]" { in_globals=0; print; next }
    in_globals && /^port=/ { print "port=" port; next }
    in_globals && /^autorun=/ { print "autorun=Xvnc"; next }
    in_globals && /^certificate=/ { print "certificate=" cert; next }
    in_globals && /^key_file=/ { print "key_file=" key; next }
    in_globals && /^#xrdp.override_keyboard_type=/ { print "xrdp.override_keyboard_type=0x04"; next }
    in_globals && /^#xrdp.override_keyboard_subtype=/ { print "xrdp.override_keyboard_subtype=0x01"; next }
    in_globals && /^#xrdp.override_keylayout=/ { print "xrdp.override_keylayout=" keylayout; next }
    { print }
  ' /etc/xrdp/xrdp.ini > /etc/xrdp/xrdp.ini.tmp
  mv /etc/xrdp/xrdp.ini.tmp /etc/xrdp/xrdp.ini

  if ! grep -q '^autorun=Xvnc$' /etc/xrdp/xrdp.ini; then
    awk '
      /^\[Globals\]/ { print; print "autorun=Xvnc"; next }
      { print }
    ' /etc/xrdp/xrdp.ini > /etc/xrdp/xrdp.ini.tmp
    mv /etc/xrdp/xrdp.ini.tmp /etc/xrdp/xrdp.ini
  fi

  awk '
    /^\[Xvnc\]/ { in_xvnc=1; print; next }
    /^\[/ && $0 != "[Xvnc]" { in_xvnc=0; print; next }
    in_xvnc && /^param=Xvnc$/ { print "param=/usr/bin/Xtigervnc"; next }
    in_xvnc && /^param=-localhost$/ { print; print "param=-SecurityTypes"; print "param=None"; next }
    { print }
  ' /etc/xrdp/sesman.ini > /etc/xrdp/sesman.ini.tmp
  mv /etc/xrdp/sesman.ini.tmp /etc/xrdp/sesman.ini

  cat > /etc/xrdp/startwm.sh <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/pob-flatpak-session
EOF
  chmod +x /etc/xrdp/startwm.sh
}

ensure_flatpak_remotes() {
  flatpak remote-add --system --if-not-exists --no-gpg-verify "$POB_FLATPAK_LOCAL_REMOTE" "file://${POB_FLATPAK_REPO_DIR}"
}

install_flatpak_app() {
  log "Installing ${POB_FLATPAK_APP_ID} from ${POB_FLATPAK_LOCAL_REMOTE}"
  flatpak install -y --noninteractive --system --or-update "$POB_FLATPAK_LOCAL_REMOTE" "$POB_FLATPAK_APP_ID"
}

start_sesman() {
  log "Starting xrdp-sesman"
  /usr/sbin/xrdp-sesman --nodaemon >"$LOG_DIR/xrdp-sesman.log" 2>&1 &
  pids+=("$!")
}

require_dir "$BUILD_DIR" "Mounted build directory"
require_dir "$POB_FLATPAK_REPO_DIR" "Mounted flatpak repo"
if [[ ! -f "$POB_RDP_CERT_FILE" || ! -f "$POB_RDP_KEY_FILE" ]]; then
  log "RDP TLS files are missing: cert=$POB_RDP_CERT_FILE key=$POB_RDP_KEY_FILE"
  exit 1
fi

prepare_runtime_dirs
configure_root_password
configure_xrdp
ensure_flatpak_remotes
install_flatpak_app
start_sesman
log "Starting xrdp on port $POB_RDP_PORT"
exec /usr/sbin/xrdp --nodaemon >"$LOG_DIR/xrdp.log" 2>&1
