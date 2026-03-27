#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/flatpak-common.sh"

"${REPO_ROOT}/scripts/flatpak-run.sh" "$@"
"${REPO_ROOT}/scripts/start-idle-watch.sh"
