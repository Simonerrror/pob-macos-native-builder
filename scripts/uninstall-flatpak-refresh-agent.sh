#!/usr/bin/env bash
set -euo pipefail

AGENT_LABEL="dev.sergio.pob.flatpak-refresh"
AGENT_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

launchctl bootout "gui/$(id -u)" "$AGENT_PATH" >/dev/null 2>&1 || true
rm -f "$AGENT_PATH"

printf 'Removed launchd agent: %s\n' "$AGENT_PATH"
