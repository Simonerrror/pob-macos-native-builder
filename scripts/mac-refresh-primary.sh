#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/mac-common.sh"

fail() {
  printf '[mac-native] ERROR: %s\n' "$*" >&2
  exit 1
}

json_field() {
  local json="$1"
  local field="$2"
  python3 - "$json" "$field" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload[sys.argv[2]]
if value is None:
    raise SystemExit(f"Release metadata has no {sys.argv[2]}")
print(value)
PY
}

verify_final_release() {
  local json="$1"
  local expected_tag="$2"
  local label="$3"
  python3 - "$json" "$expected_tag" "$label" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
expected_tag, label = sys.argv[2:]
if payload.get("tag_name") != expected_tag:
    raise SystemExit(f"{label} release tag mismatch: expected {expected_tag}, got {payload.get('tag_name')}")
if payload.get("draft") is not False:
    raise SystemExit(f"{label} release is not confirmed final: draft={payload.get('draft')}")
if payload.get("prerelease") is not False:
    raise SystemExit(f"{label} release is not confirmed final: prerelease={payload.get('prerelease')}")
if not isinstance(payload.get("published_at"), str) or not payload["published_at"]:
    raise SystemExit(f"{label} release has no published_at timestamp")
PY
}

select_compatible_rusty_tag() {
  local minimum_version="$1"
  local releases_json="$2"
  local requested_tag="${3:-}"
  python3 - "$minimum_version" "$releases_json" "$requested_tag" <<'PY'
import json
import re
import sys

def parse(version):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        raise ValueError(version)
    return tuple(int(part) for part in match.groups())

try:
    minimum = parse(sys.argv[1])
except ValueError:
    raise SystemExit(f"Invalid minimum Rusty version: {sys.argv[1]}")

releases = json.loads(sys.argv[2])
requested_tag = sys.argv[3]
best = None
for release in releases:
    tag = release.get("tag_name") or ""
    if release.get("draft") is not False or release.get("prerelease") is not False:
        continue
    if not release.get("published_at"):
        continue
    try:
        version = parse(tag)
    except ValueError:
        continue
    if version < minimum:
        continue
    if requested_tag:
        if tag == requested_tag:
            print(tag)
            raise SystemExit(0)
        continue
    if best is None or version > best[0]:
        best = (version, tag)

if requested_tag:
    raise SystemExit(f"Configured Rusty release {requested_tag} is not a final compatible release")
if best is None:
    raise SystemExit(f"No final Rusty release satisfies minimum {sys.argv[1]}")
print(best[1])
PY
}

mirror_url_for_repo() {
  printf 'https://github.com/%s.git\n' "$1"
}

ensure_git_mirror() {
  local mirror="$1"
  local remote_url="$2"
  local label="$3"
  local bootstrap_path origin_url is_bare

  mkdir -p "$(dirname "$mirror")"
  if [[ ! -e "$mirror" ]]; then
    bootstrap_path="${mirror}.bootstrap.$$"
    [[ ! -e "$bootstrap_path" ]] || fail "Temporary mirror bootstrap path already exists: ${bootstrap_path}"
    log "Bootstrapping ${label} git mirror from the official GitHub repository"
    if ! git clone --mirror "$remote_url" "$bootstrap_path"; then
      rm -rf "$bootstrap_path"
      fail "Upstream-access/bootstrap blocker: failed to clone ${label} git mirror"
    fi
    is_bare="$(git --git-dir="$bootstrap_path" rev-parse --is-bare-repository 2>/dev/null || true)"
    origin_url="$(git --git-dir="$bootstrap_path" config --get remote.origin.url 2>/dev/null || true)"
    if [[ "$is_bare" != true || "$origin_url" != "$remote_url" ]]; then
      rm -rf "$bootstrap_path"
      fail "Bootstrap produced an invalid ${label} git mirror"
    fi
    mv "$bootstrap_path" "$mirror"
  fi

  is_bare="$(git --git-dir="$mirror" rev-parse --is-bare-repository 2>/dev/null || true)"
  [[ "$is_bare" == true ]] || fail "Upstream-access/bootstrap blocker: existing ${label} mirror is not a valid bare Git repository: ${mirror}"
  origin_url="$(git --git-dir="$mirror" config --get remote.origin.url 2>/dev/null || true)"
  [[ "$origin_url" == "$remote_url" ]] || fail "Upstream-access/bootstrap blocker: existing ${label} mirror origin mismatch: ${origin_url:-missing origin}"

  log "Fetching ${label} tags and branch deltas into the persistent mirror"
  if ! git --git-dir="$mirror" fetch --prune origin \
    '+refs/heads/*:refs/heads/*' \
    '+refs/tags/*:refs/tags/*'; then
    fail "Upstream-access/bootstrap blocker: delta fetch failed for ${label} git mirror"
  fi
}

peeled_commit_for_tag() {
  local mirror="$1"
  local tag="$2"
  local label="$3"
  local commit

  if ! commit="$(git --git-dir="$mirror" rev-parse --verify "${tag}^{commit}" 2>/dev/null)"; then
    fail "Upstream-access/bootstrap blocker: ${label} release tag ${tag} is missing from its Git mirror"
  fi
  [[ "$commit" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || fail "Invalid peeled commit SHA for ${label} ${tag}: ${commit}"
  printf '%s\n' "$commit"
}

checkout_mirror_commit() {
  local mirror="$1"
  local commit="$2"
  local destination="$3"
  local label="$4"
  local actual

  mkdir -p "$(dirname "$destination")"
  if ! git clone --shared --no-checkout "$mirror" "$destination"; then
    fail "Upstream-access/bootstrap blocker: failed to materialize ${label} source from its mirror"
  fi
  if ! git -C "$destination" checkout --detach "$commit"; then
    fail "Upstream-access/bootstrap blocker: exact ${label} commit ${commit} is incomplete in its mirror"
  fi
  actual="$(git -C "$destination" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || fail "Materialized ${label} source at ${actual}; expected ${commit}"
}

write_release_metadata() {
  local output="$1"
  local pob_tag="$2"
  local pob_version="$3"
  local pob_published_at="$4"
  local pob_commit="$5"
  local rusty_tag="$6"
  local rusty_version="$7"
  local rusty_published_at="$8"
  local rusty_commit="$9"
  local minimum_rusty="${10}"
  local saved_metadata_path="$VERSION_METADATA_FILE"

  VERSION_METADATA_FILE="$output"
  write_version_metadata \
    "$pob_tag" "$pob_version" "$pob_published_at" \
    "$rusty_tag" "$rusty_version" "$rusty_published_at" "$minimum_rusty"
  VERSION_METADATA_FILE="$saved_metadata_path"

  python3 - "$output" "$pob_commit" "$rusty_commit" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["pob"]["commit"] = sys.argv[2]
payload["rusty"]["commit"] = sys.argv[3]
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

prepare_build_workspace() {
  local work_repo="$1"
  mkdir -p \
    "${work_repo}/scripts" \
    "${work_repo}/macos" \
    "${work_repo}/.state/macos" \
    "${work_repo}/.cache/macos/downloads"
  cp -p \
    "${REPO_ROOT}/scripts/mac-common.sh" \
    "${REPO_ROOT}/scripts/mac-build.sh" \
    "${REPO_ROOT}/scripts/mac-bundle.sh" \
    "${REPO_ROOT}/scripts/mac-smoke-test.sh" \
    "${work_repo}/scripts/"
  cp -p "${REPO_ROOT}/macos/launcher.sh" "${work_repo}/macos/launcher.sh"
  mkdir -p "${DOWNLOADS_ROOT}/vendor"
  ln -s "${DOWNLOADS_ROOT}/vendor" "${work_repo}/.cache/macos/downloads/vendor"
}

bundle_matches_metadata() {
  local metadata_file="$1"
  local bundle_dir="$2"
  python3 - "$metadata_file" "$bundle_dir" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
bundle = Path(sys.argv[2])
bundle_metadata_path = bundle / "Contents/Resources/metadata/version.json"
plist_path = bundle / "Contents/Info.plist"
try:
    expected = json.loads(metadata_path.read_text(encoding="utf-8"))
    actual = json.loads(bundle_metadata_path.read_text(encoding="utf-8"))
    with plist_path.open("rb") as handle:
        info = plistlib.load(handle)
except (OSError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException):
    raise SystemExit(1)

if expected != actual:
    raise SystemExit("bundle metadata differs from staged release metadata")
if info.get("CFBundleShortVersionString") != actual.get("pob", {}).get("version"):
    raise SystemExit("Info.plist short version differs from bundle metadata")
if info.get("CFBundleVersion") != actual.get("version_id"):
    raise SystemExit("Info.plist bundle version differs from bundle metadata")
PY
}

current_release_is_installed() {
  local pob_tag="$1"
  local pob_version="$2"
  local pob_commit="$3"
  local rusty_tag="$4"
  local rusty_version="$5"
  local rusty_commit="$6"

  python3 - "$VERSION_METADATA_FILE" "$POB_MAC_BUNDLE_PATH" "$POB_MAC_GAME" \
    "$pob_tag" "$pob_version" "$pob_commit" "$rusty_tag" "$rusty_version" "$rusty_commit" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
bundle = Path(sys.argv[2])
game = sys.argv[3]
pob_tag, pob_version, pob_commit, rusty_tag, rusty_version, rusty_commit = sys.argv[4:]
try:
    state = json.loads(state_path.read_text(encoding="utf-8"))
    bundle_metadata = json.loads((bundle / "Contents/Resources/metadata/version.json").read_text(encoding="utf-8"))
    with (bundle / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
except (OSError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException):
    raise SystemExit(1)

expected_version_id = f"{pob_tag}--{rusty_tag}"
for payload in (state, bundle_metadata):
    if payload.get("game") != game or payload.get("version_id") != expected_version_id:
        raise SystemExit(1)
    if payload.get("pob", {}).get("tag") != pob_tag:
        raise SystemExit(1)
    if payload.get("pob", {}).get("version") != pob_version:
        raise SystemExit(1)
    if payload.get("pob", {}).get("commit") != pob_commit:
        raise SystemExit(1)
    if payload.get("rusty", {}).get("tag") != rusty_tag:
        raise SystemExit(1)
    if payload.get("rusty", {}).get("version") != rusty_version:
        raise SystemExit(1)
    if payload.get("rusty", {}).get("commit") != rusty_commit:
        raise SystemExit(1)
if state != bundle_metadata:
    raise SystemExit(1)
if info.get("CFBundleShortVersionString") != pob_version:
    raise SystemExit(1)
if info.get("CFBundleVersion") != expected_version_id:
    raise SystemExit(1)
PY
}

smoke_bundle() {
  local script_root="$1"
  local bundle_dir="$2"
  local smoke_root="$3"
  local mode="${4:-static}"

  if [[ "$mode" == launch ]]; then
    POB_MAC_BUNDLE_PATH="$bundle_dir" \
    POB_MAC_SUPPORT_DIR="${smoke_root}/Path of Building" \
    POB_BUILDS_HOST_DIR="${smoke_root}/Builds" \
    POB_MAC_SMOKE_TIMEOUT_SECONDS="${POB_MAC_SMOKE_TIMEOUT_SECONDS:-45}" \
      "${script_root}/scripts/mac-smoke-test.sh" --launch
  else
    POB_MAC_BUNDLE_PATH="$bundle_dir" \
    POB_MAC_SUPPORT_DIR="${smoke_root}/Path of Building" \
    POB_BUILDS_HOST_DIR="${smoke_root}/Builds" \
    POB_MAC_SMOKE_TIMEOUT_SECONDS="${POB_MAC_SMOKE_TIMEOUT_SECONDS:-45}" \
      "${script_root}/scripts/mac-smoke-test.sh"
  fi
}

update_last_refresh() {
  date '+%Y-%m-%d %H:%M:%S %z' > "$LAST_REFRESH_FILE"
}

rollback_promotion() {
  local rollback_failed=0

  if [[ "$METADATA_PROMOTED" -eq 1 ]]; then
    if [[ "$HAD_PREVIOUS_METADATA" -eq 1 ]]; then
      local metadata_restore="${VERSION_METADATA_FILE}.rollback.$$"
      if cp -p "$STATE_BACKUP" "$metadata_restore" && mv "$metadata_restore" "$VERSION_METADATA_FILE"; then
        log "Restored pre-refresh version metadata during rollback"
      else
        rm -f "$metadata_restore"
        printf '[mac-native] ERROR: failed to restore version metadata from %s\n' "$STATE_BACKUP" >&2
        rollback_failed=1
      fi
    elif ! rm -f "$VERSION_METADATA_FILE"; then
      printf '[mac-native] ERROR: failed to remove newly promoted version metadata during rollback\n' >&2
      rollback_failed=1
    fi
  fi

  if [[ "$NEW_BUNDLE_INSTALLED" -eq 1 ]]; then
    if [[ -e "$POB_MAC_BUNDLE_PATH" || -L "$POB_MAC_BUNDLE_PATH" ]]; then
      if [[ -e "$NEXT_APP" || -L "$NEXT_APP" ]]; then
        printf '[mac-native] ERROR: candidate path is occupied during rollback: %s\n' "$NEXT_APP" >&2
        rollback_failed=1
      elif mv "$POB_MAC_BUNDLE_PATH" "$NEXT_APP"; then
        log "Moved the unverified bundle back to the candidate path during rollback"
      else
        printf '[mac-native] ERROR: failed to move the unverified app back to %s\n' "$NEXT_APP" >&2
        rollback_failed=1
      fi
    elif [[ ! -e "$NEXT_APP" && ! -L "$NEXT_APP" ]]; then
      printf '[mac-native] ERROR: unverified bundle is missing from both installed and candidate paths\n' >&2
      rollback_failed=1
    fi
  fi

  if [[ "$OLD_BUNDLE_MOVED" -eq 1 ]]; then
    if [[ -e "$PREVIOUS_APP" || -L "$PREVIOUS_APP" ]]; then
      if [[ -e "$POB_MAC_BUNDLE_PATH" || -L "$POB_MAC_BUNDLE_PATH" ]]; then
        printf '[mac-native] ERROR: cannot restore previous app because canonical path is occupied\n' >&2
        rollback_failed=1
      elif mv "$PREVIOUS_APP" "$POB_MAC_BUNDLE_PATH"; then
        log "Restored the previously installed app during rollback"
      else
        printf '[mac-native] ERROR: failed to restore the previous app from %s\n' "$PREVIOUS_APP" >&2
        rollback_failed=1
      fi
    elif [[ ! -e "$POB_MAC_BUNDLE_PATH" && ! -L "$POB_MAC_BUNDLE_PATH" ]]; then
      printf '[mac-native] ERROR: previous app is missing from both installed and previous paths\n' >&2
      rollback_failed=1
    else
      log "Previously installed app remained at the canonical path during rollback"
    fi
  fi

  [[ "$rollback_failed" -eq 0 ]]
}

finish() {
  local status=$?
  local rollback_ok=1
  trap - EXIT
  if [[ "$status" -ne 0 && "$PROMOTION_COMMITTED" -eq 0 ]]; then
    if ! rollback_promotion; then
      status=1
      rollback_ok=0
    elif [[ -n "$STATE_BACKUP" && -e "$STATE_BACKUP" ]]; then
      rm -f "$STATE_BACKUP" || status=1
    fi
  fi
  if [[ "$PROMOTION_COMMITTED" -eq 1 && -n "$STATE_BACKUP" && -e "$STATE_BACKUP" ]]; then
    rm -f "$STATE_BACKUP" || status=1
  fi
  if [[ -n "$PENDING_METADATA" && -e "$PENDING_METADATA" ]]; then
    rm -f "$PENDING_METADATA" || status=1
  fi
  if [[ "$status" -ne 0 && "$PROMOTION_COMMITTED" -eq 0 && "$rollback_ok" -eq 1 \
    && -n "$NEXT_APP" && ( -e "$NEXT_APP" || -L "$NEXT_APP" ) ]]; then
    if rm -rf "$NEXT_APP"; then
      log "Removed the unverified candidate bundle after rollback"
    else
      printf '[mac-native] ERROR: failed to remove unverified candidate bundle: %s\n' "$NEXT_APP" >&2
      status=1
    fi
  fi
  if [[ -n "$SMOKE_ROOT" && ( -e "$SMOKE_ROOT" || -L "$SMOKE_ROOT" ) ]]; then
    rm -rf "$SMOKE_ROOT" || status=1
  fi
  if [[ -n "$RUN_ROOT" && ( -e "$RUN_ROOT" || -L "$RUN_ROOT" ) ]]; then
    rm -rf "$RUN_ROOT" || status=1
  fi
  if [[ "$LOCK_ACQUIRED" -eq 1 ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  exit "$status"
}

ensure_mac_dirs
require_cmd curl
require_cmd jq
require_cmd git
require_cmd python3

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "Another native macOS refresh is in progress; refusing to start a second pipeline"
fi

RUN_ROOT=""
SMOKE_ROOT=""
STATE_BACKUP=""
PENDING_METADATA=""
LOCK_ACQUIRED=1
OLD_BUNDLE_MOVED=0
NEW_BUNDLE_INSTALLED=0
METADATA_PROMOTED=0
HAD_PREVIOUS_METADATA=0
PROMOTION_COMMITTED=0
NEXT_APP=""
PREVIOUS_APP=""
trap finish EXIT

bundle_parent="$(dirname "$POB_MAC_BUNDLE_PATH")"
bundle_stem="$(basename "$POB_MAC_BUNDLE_PATH")"
[[ "$bundle_stem" == *.app ]] || fail "Configured app bundle path must end in .app: ${POB_MAC_BUNDLE_PATH}"
bundle_stem="${bundle_stem%.app}"
NEXT_APP="${bundle_parent}/${bundle_stem}.next.app"
PREVIOUS_APP="${bundle_parent}/${bundle_stem}.previous.app"

[[ ! -e "$NEXT_APP" && ! -L "$NEXT_APP" ]] || fail "Candidate bundle path already exists; inspect before retrying: ${NEXT_APP}"
[[ ! -e "$PREVIOUS_APP" && ! -L "$PREVIOUS_APP" ]] || fail "Previous bundle path already exists; inspect before retrying: ${PREVIOUS_APP}"

if ! pob_tag="$(resolve_pob_tag latest)"; then
  fail "Upstream-access/bootstrap blocker: unable to resolve the latest final Path of Building release"
fi
pob_repo="$(game_repo)"
if ! pob_release_json="$(github_api "https://api.github.com/repos/${pob_repo}/releases/tags/${pob_tag}")"; then
  fail "Upstream-access/bootstrap blocker: unable to read official Path of Building release metadata for ${pob_tag}"
fi
if ! verify_final_release "$pob_release_json" "$pob_tag" "Path of Building"; then
  fail "Upstream release metadata did not confirm ${pob_tag} as a final release"
fi
pob_version="$(strip_v "$(json_field "$pob_release_json" tag_name)")"
pob_published_at="$(json_field "$pob_release_json" published_at)"

if ! download_compatibility_file; then
  fail "Upstream-access/bootstrap blocker: unable to download the PoB/Rusty compatibility manifest"
fi
minimum_rusty="$(minimum_rusty_version_for_pob "$pob_version" "$(compat_file_path)")" || \
  fail "Upstream compatibility manifest has no Rusty requirement for PoB ${pob_version}"

if ! rusty_releases_json="$(github_api "https://api.github.com/repos/${POB_MAC_RUSTY_REPO}/releases?per_page=100")"; then
  fail "Upstream-access/bootstrap blocker: unable to read Rusty release metadata"
fi
if ! rusty_tag="$(select_compatible_rusty_tag "$minimum_rusty" "$rusty_releases_json" "${POB_MAC_RUSTY_TAG:-}")"; then
  fail "Upstream release metadata has no final Rusty release satisfying ${minimum_rusty}"
fi
if ! rusty_release_json="$(github_api "https://api.github.com/repos/${POB_MAC_RUSTY_REPO}/releases/tags/${rusty_tag}")"; then
  fail "Upstream-access/bootstrap blocker: unable to read official Rusty release metadata for ${rusty_tag}"
fi
if ! verify_final_release "$rusty_release_json" "$rusty_tag" "Rusty"; then
  fail "Upstream release metadata did not confirm ${rusty_tag} as a final release"
fi
rusty_version="$(strip_v "$(json_field "$rusty_release_json" tag_name)")"
rusty_published_at="$(json_field "$rusty_release_json" published_at)"

POB_MIRROR="${CACHE_ROOT}/git/pob.git"
RUSTY_MIRROR="${CACHE_ROOT}/git/rusty.git"
mkdir -p "${CACHE_ROOT}/git"
ensure_git_mirror "$POB_MIRROR" "$(mirror_url_for_repo "$pob_repo")" "Path of Building"
ensure_git_mirror "$RUSTY_MIRROR" "$(mirror_url_for_repo "$POB_MAC_RUSTY_REPO")" "Rusty"
log "Git mirror delta sync complete"

pob_commit="$(peeled_commit_for_tag "$POB_MIRROR" "$pob_tag" "Path of Building")"
rusty_commit="$(peeled_commit_for_tag "$RUSTY_MIRROR" "$rusty_tag" "Rusty")"
log "Resolved final releases: PoB ${pob_tag} (${pob_commit}); Rusty ${rusty_tag} (${rusty_commit})"

if current_release_is_installed \
  "$pob_tag" "$pob_version" "$pob_commit" \
  "$rusty_tag" "$rusty_version" "$rusty_commit"; then
  log "Official releases are unchanged; verifying the installed canonical bundle without rebuilding"
  SMOKE_ROOT="$(mktemp -d "${BUILD_ROOT}/primary-smoke-XXXXXX")"
  smoke_bundle "$REPO_ROOT" "$POB_MAC_BUNDLE_PATH" "$SMOKE_ROOT" static
  smoke_bundle "$REPO_ROOT" "$POB_MAC_BUNDLE_PATH" "$SMOKE_ROOT" launch
  bundle_matches_metadata "$VERSION_METADATA_FILE" "$POB_MAC_BUNDLE_PATH" || \
    fail "Installed bundle metadata or Info.plist no longer matches current-version.json"
  rm -rf "$SMOKE_ROOT"
  SMOKE_ROOT=""
  update_last_refresh
  log "No-op refresh complete; the installed app passed static and launch smoke"
  exit 0
fi

RUN_ROOT="$(mktemp -d "${BUILD_ROOT}/primary-run-XXXXXX")"
WORK_REPO="${RUN_ROOT}/repo"
POB_SOURCE="${WORK_REPO}/.cache/macos/upstream/pob/${pob_tag}"
RUSTY_SOURCE="${WORK_REPO}/.cache/macos/upstream/rusty/${rusty_tag}"
CANDIDATE_METADATA="${WORK_REPO}/.state/macos/current-version.json"
SMOKE_ROOT="${RUN_ROOT}/smoke"

prepare_build_workspace "$WORK_REPO"
write_release_metadata \
  "$CANDIDATE_METADATA" \
  "$pob_tag" "$pob_version" "$pob_published_at" "$pob_commit" \
  "$rusty_tag" "$rusty_version" "$rusty_published_at" "$rusty_commit" "$minimum_rusty"

checkout_mirror_commit "$POB_MIRROR" "$pob_commit" "$POB_SOURCE" "Path of Building"
checkout_mirror_commit "$RUSTY_MIRROR" "$rusty_commit" "$RUSTY_SOURCE" "Rusty"
log "Source checkouts are pinned to the peeled release commits"

if [[ -e "$POB_MAC_BUNDLE_PATH" || -L "$POB_MAC_BUNDLE_PATH" ]]; then
  [[ -d "$POB_MAC_BUNDLE_PATH" ]] || fail "Installed app path is not a directory: ${POB_MAC_BUNDLE_PATH}"
fi

log "Building candidate app at ${NEXT_APP}"
"${WORK_REPO}/scripts/mac-build.sh"
POB_MAC_BUNDLE_PATH="$NEXT_APP" "${WORK_REPO}/scripts/mac-bundle.sh"
[[ -d "$NEXT_APP" ]] || fail "Bundle step did not produce candidate app: ${NEXT_APP}"
bundle_matches_metadata "$CANDIDATE_METADATA" "$NEXT_APP" || \
  fail "Candidate metadata or Info.plist differs from resolved release metadata"

log "Running candidate static smoke"
smoke_bundle "$WORK_REPO" "$NEXT_APP" "${SMOKE_ROOT}/candidate" static
log "Running candidate launch smoke"
smoke_bundle "$WORK_REPO" "$NEXT_APP" "${SMOKE_ROOT}/candidate" launch

log "Atomically installing the smoke-tested candidate"
if [[ -e "$POB_MAC_BUNDLE_PATH" || -L "$POB_MAC_BUNDLE_PATH" ]]; then
  OLD_BUNDLE_MOVED=1
  mv "$POB_MAC_BUNDLE_PATH" "$PREVIOUS_APP"
fi
NEW_BUNDLE_INSTALLED=1
mv "$NEXT_APP" "$POB_MAC_BUNDLE_PATH"

log "Running final static smoke on the installed canonical bundle"
smoke_bundle "$WORK_REPO" "$POB_MAC_BUNDLE_PATH" "${SMOKE_ROOT}/final" static
log "Running final launch smoke on the installed canonical bundle"
smoke_bundle "$WORK_REPO" "$POB_MAC_BUNDLE_PATH" "${SMOKE_ROOT}/final" launch
bundle_matches_metadata "$CANDIDATE_METADATA" "$POB_MAC_BUNDLE_PATH" || \
  fail "Installed canonical bundle metadata or Info.plist differs from the candidate"

STATE_BACKUP="${MAC_STATE_ROOT}/.current-version.previous.$$"
[[ ! -e "$STATE_BACKUP" ]] || fail "Metadata rollback path already exists: ${STATE_BACKUP}"
if [[ -f "$VERSION_METADATA_FILE" ]]; then
  cp -p "$VERSION_METADATA_FILE" "$STATE_BACKUP"
  HAD_PREVIOUS_METADATA=1
fi
PENDING_METADATA="${VERSION_METADATA_FILE}.pending.$$"
[[ ! -e "$PENDING_METADATA" ]] || fail "Metadata promotion path already exists: ${PENDING_METADATA}"
cp "$CANDIDATE_METADATA" "$PENDING_METADATA"
METADATA_PROMOTED=1
mv "$PENDING_METADATA" "$VERSION_METADATA_FILE"
PENDING_METADATA=""

# Keep the prior bundle and metadata backup until all other owned build artifacts are gone.
rm -rf "$RUN_ROOT"
RUN_ROOT=""
update_last_refresh
PROMOTION_COMMITTED=1

if [[ "$OLD_BUNDLE_MOVED" -eq 1 ]]; then
  rm -rf "$PREVIOUS_APP" || fail "Verified app was promoted, but previous bundle cleanup failed: ${PREVIOUS_APP}"
  OLD_BUNDLE_MOVED=0
fi
if [[ "$HAD_PREVIOUS_METADATA" -eq 1 ]]; then
  rm -f "$STATE_BACKUP" || fail "Verified app was promoted, but metadata backup cleanup failed: ${STATE_BACKUP}"
fi
STATE_BACKUP=""

log "Native macOS refresh complete for ${pob_tag} / ${rusty_tag}"
