#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_CONTEXT_ARG=()

if [[ -n "${POB_DOCKER_CONTEXT:-}" ]]; then
  DOCKER_CONTEXT_ARG=(--context "$POB_DOCKER_CONTEXT")
elif docker context inspect orbstack >/dev/null 2>&1; then
  DOCKER_CONTEXT_ARG=(--context orbstack)
fi

exec docker "${DOCKER_CONTEXT_ARG[@]}" compose -f "${REPO_ROOT}/docker-compose.yml" logs -f "$@"
