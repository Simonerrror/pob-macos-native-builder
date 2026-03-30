#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_LABEL="dev.sergio.pob.mac-native-refresh"
AGENT_PATH="${AGENT_DIR}/${AGENT_LABEL}.plist"
OLD_FLATPAK_AGENT_PATH="${AGENT_DIR}/dev.sergio.pob.flatpak-refresh.plist"
LOG_DIR="${REPO_ROOT}/.state/logs"
WEEKDAY="${POB_MAC_REFRESH_WEEKDAY:-6}"
HOUR="${POB_MAC_REFRESH_HOUR:-19}"
MINUTE="${POB_MAC_REFRESH_MINUTE:-0}"
PATH_VALUE="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$AGENT_DIR" "$LOG_DIR"

launchctl bootout "gui/$(id -u)" "$OLD_FLATPAK_AGENT_PATH" >/dev/null 2>&1 || true

cat >"$AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_LABEL}</string>
  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>export PATH="${PATH_VALUE}"; exec "${REPO_ROOT}/scripts/mac-refresh.sh"</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${PATH_VALUE}</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>${WEEKDAY}</integer>
    <key>Hour</key>
    <integer>${HOUR}</integer>
    <key>Minute</key>
    <integer>${MINUTE}</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/mac-native-refresh.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/mac-native-refresh.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$AGENT_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_PATH"
launchctl enable "gui/$(id -u)/${AGENT_LABEL}"

printf 'Installed launchd agent: %s\n' "$AGENT_PATH"
printf 'Schedule: weekday=%s at %02d:%02d local time\n' "$WEEKDAY" "$HOUR" "$MINUTE"
printf 'Logs: %s/mac-native-refresh.log\n' "$LOG_DIR"
