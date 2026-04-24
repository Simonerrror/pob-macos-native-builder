#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

AGENT_LABEL="${POB_MAC_REFRESH_AGENT_LABEL:-dev.local.pathofbuilding.mac-native-refresh}"
AGENT_PATH="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"

launchctl bootout "gui/$(id -u)" "$AGENT_PATH" >/dev/null 2>&1 || true
rm -f "$AGENT_PATH"

printf 'Removed launchd agent: %s\n' "$AGENT_PATH"
