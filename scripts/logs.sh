#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flatpak-common.sh"

exec docker "${DOCKER_CONTEXT_ARG[@]}" compose -f "${REPO_ROOT}/docker-compose.flatpak.yml" logs -f "$@"
