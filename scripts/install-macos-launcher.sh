#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-${HOME}/Desktop}"
TARGET_PATH="${TARGET_DIR}/POB.command"

mkdir -p "$TARGET_DIR"
cat >"$TARGET_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${REPO_ROOT}"
exec "${REPO_ROOT}/scripts/mac-launch.sh"
EOF
chmod +x "$TARGET_PATH"

printf 'Installed launcher: %s\n' "$TARGET_PATH"
