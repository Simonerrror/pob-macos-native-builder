#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -E -q -- "$pattern" "$file" || fail "expected '$pattern' in $file"
}

assert_no_refresh_artifacts() {
  local root="$1"
  [[ ! -e "$root/dist/Path of Building.next.app" ]] || fail "candidate bundle remains in $root"
  [[ ! -e "$root/dist/Path of Building.previous.app" ]] || fail "previous bundle remains in $root"
  [[ ! -e "$root/.state/macos/current-version.candidate.json" ]] || fail "candidate metadata remains in $root"
  if find "$root/.cache/macos/build" -type d -name 'primary-*' -print -quit 2>/dev/null | grep -q .; then
    fail "temporary refresh workspace remains in $root"
  fi
}

[[ -x "$REPO_ROOT/scripts/mac-refresh-primary.sh" ]] || fail "scripts/mac-refresh-primary.sh is missing or not executable"

make_fixture_helpers() {
  local root="$1"
  mkdir -p "$root/bin" "$root/scripts" "$root/macos" "$root/tests" "$root/.state/macos" "$root/.cache/macos/git" "$root/.cache/macos/downloads/vendor" "$root/dist"

  cp "$REPO_ROOT/scripts/mac-common.sh" "$root/scripts/mac-common.sh"
  cp "$REPO_ROOT/scripts/mac-refresh-primary.sh" "$root/scripts/mac-refresh-primary.sh"
  cp "$REPO_ROOT/macos/launcher.sh" "$root/macos/launcher.sh"
  chmod +x "$root/scripts/mac-refresh-primary.sh"

  cat > "$root/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output="${args[$((i + 1))]}"
  fi
done
url=""
for arg in "${args[@]}"; do
  case "$arg" in
    https://*) url="$arg" ;;
  esac
done
case "$url" in
  https://api.github.com/repos/PathOfBuildingCommunity/PathOfBuilding/releases/latest)
    printf '%s\n' '{"tag_name":"v2.67.3"}'
    ;;
  https://api.github.com/repos/PathOfBuildingCommunity/PathOfBuilding/releases/tags/v2.67.3)
    printf '%s\n' '{"tag_name":"v2.67.3","draft":false,"prerelease":false,"published_at":"2026-09-11T12:00:00Z"}'
    ;;
  https://api.github.com/repos/meehl/rusty-path-of-building/releases\?per_page=100)
    printf '%s\n' '[{"tag_name":"v0.2.19","draft":false,"prerelease":false,"published_at":"2026-09-10T12:00:00Z"},{"tag_name":"v0.2.20","draft":false,"prerelease":true,"published_at":"2026-09-12T12:00:00Z"}]'
    ;;
  https://api.github.com/repos/meehl/rusty-path-of-building/releases/tags/v0.2.19)
    printf '%s\n' '{"tag_name":"v0.2.19","draft":false,"prerelease":false,"published_at":"2026-09-10T12:00:00Z"}'
    ;;
  https://raw.githubusercontent.com/meehl/rusty-pob-manifest/main/Compatibility_pob1.lua)
    [[ -n "$output" ]] || { printf 'missing curl -o target\n' >&2; exit 2; }
    printf '%s\n' 'compat["2.67.3"] = "0.2.19"' > "$output"
    ;;
  *)
    printf 'unexpected network URL: %s\n' "$url" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$root/bin/curl"

  cat > "$root/bin/jq" <<'SH'
#!/usr/bin/env python3
import json
import sys

query = sys.argv[-1]
payload = json.load(sys.stdin)
if query == ".tag_name":
    value = payload["tag_name"]
else:
    raise SystemExit(f"unsupported test jq query: {query}")
print(value)
SH
  chmod +x "$root/bin/jq"

  cat > "$root/tests/fake-bundle.py" <<'PY'
#!/usr/bin/env python3
import json
import plistlib
import sys
from pathlib import Path

metadata_source = Path(sys.argv[1])
bundle = Path(sys.argv[2])
run_log = Path(sys.argv[3])
with metadata_source.open("r", encoding="utf-8") as handle:
    metadata = json.load(handle)

contents = bundle / "Contents"
launcher = contents / "MacOS" / "Path of Building"
runtime = contents / "Resources" / "runtime" / "bin" / "rusty-path-of-building"
payload = contents / "Resources" / "payload" / "current"
metadata_dir = contents / "Resources" / "metadata"
launcher.parent.mkdir(parents=True, exist_ok=True)
runtime.parent.mkdir(parents=True, exist_ok=True)
payload.mkdir(parents=True, exist_ok=True)
metadata_dir.mkdir(parents=True, exist_ok=True)
(payload / "Launch.lua").write_text('print("fixture")\n', encoding="utf-8")
(metadata_dir / "version.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
(metadata_dir / "bundle-sync-stamp").write_text(metadata["version_id"] + "\n", encoding="utf-8")
runtime.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
runtime.chmod(0o755)

plist = {
    "CFBundleExecutable": "Path of Building",
    "CFBundleIdentifier": "dev.test.pathofbuilding",
    "CFBundleName": "Path of Building",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": metadata["pob"]["version"],
    "CFBundleVersion": metadata["version_id"],
}
with (contents / "Info.plist").open("wb") as handle:
    plistlib.dump(plist, handle)

launcher.write_text(
    "#!/usr/bin/env python3\n"
    "import json, os, sys, time\n"
    "from pathlib import Path\n"
    "metadata_path = Path(__file__).parent.parent / 'Resources/metadata/version.json'\n"
    "metadata = json.loads(metadata_path.read_text(encoding='utf-8'))\n"
    "support = Path(os.environ['POB_MAC_SUPPORT_DIR'])\n"
    "script_dir = support.parent / ('RustyPathOfBuilding2' if metadata['game'] == 'poe2' else 'RustyPathOfBuilding1')\n"
    "script_dir.mkdir(parents=True, exist_ok=True)\n"
    "(script_dir / '.bundle-version').write_text(metadata['version_id'] + '\\n', encoding='utf-8')\n"
    "(script_dir / 'manifest.xml').write_text('<?xml version=\\\"1.0\\\"?><PoBVersion><Version number=\\\"' + metadata['pob']['version'] + '\\\" branch=\\\"master\\\" platform=\\\"macos\\\" /></PoBVersion>', encoding='utf-8')\n"
    "run_log = os.environ.get('POB_MAC_TEST_RUN_LOG')\n"
    "phase = 'candidate' if '.next.app' in str(metadata_path) else 'final'\n"
    "current_path = Path(os.environ['POB_MAC_TEST_CURRENT_METADATA'])\n"
    "expected_state = os.environ.get('POB_MAC_TEST_EXPECT_CURRENT_VERSION_ID')\n"
    "if expected_state and json.loads(current_path.read_text(encoding='utf-8'))['version_id'] != expected_state: raise SystemExit(9)\n"
    "canonical = Path(os.environ['POB_MAC_TEST_CANONICAL_BUNDLE'])\n"
    "sentinel = canonical / 'Contents/Resources/metadata/owner-sentinel'\n"
    "if phase == 'candidate' and not sentinel.exists(): raise SystemExit(10)\n"
    "if phase == 'final' and sentinel.exists(): raise SystemExit(11)\n"
    "if run_log:\n"
    "    with open(run_log, 'a', encoding='utf-8') as handle: handle.write('launch:' + phase + '\\n')\n"
    "if os.environ.get('POB_MAC_TEST_FAIL_CANDIDATE_LAUNCH') == '1' and phase == 'candidate': raise SystemExit(7)\n"
    "if os.environ.get('POB_MAC_TEST_FAIL_FINAL_LAUNCH') == '1' and phase == 'final': raise SystemExit(8)\n"
    "time.sleep(60)\n",
    encoding="utf-8",
)
launcher.chmod(0o755)
PY
  chmod +x "$root/tests/fake-bundle.py"

  cat > "$root/scripts/mac-build.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf '%s\n' build >> "$POB_MAC_TEST_RUN_LOG"
[[ "$(cat "$repo_root/.cache/macos/upstream/pob/v2.67.3/source-marker")" == pob-new ]] || exit 31
[[ "$(cat "$repo_root/.cache/macos/upstream/rusty/v0.2.19/source-marker")" == rusty-new ]] || exit 32
[[ -f "$repo_root/.cache/macos/downloads/vendor/preserved-cache-marker" ]] || exit 33
python3 - "$repo_root/.state/macos/current-version.json" "$POB_MAC_TEST_EXPECT_POB_SHA" "$POB_MAC_TEST_EXPECT_RUSTY_SHA" "$POB_MAC_TEST_CURRENT_METADATA" <<'PY'
import json
import sys
from pathlib import Path

candidate = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
installed = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
assert candidate["pob"]["commit"] == sys.argv[2]
assert candidate["rusty"]["commit"] == sys.argv[3]
assert installed["version_id"] == "v2.67.2--v0.2.18"
PY
[[ -d "$POB_MAC_TEST_CANONICAL_BUNDLE" ]] || exit 34
[[ -f "$POB_MAC_TEST_CANONICAL_BUNDLE/Contents/Resources/metadata/owner-sentinel" ]] || exit 35
SH
  chmod +x "$root/scripts/mac-build.sh"

  cat > "$root/scripts/mac-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$POB_MAC_BUNDLE_PATH" == "$POB_MAC_TEST_ROOT/dist/Path of Building.next.app" ]] || exit 41
[[ -d "$POB_MAC_TEST_CANONICAL_BUNDLE" ]] || exit 42
[[ -f "$POB_MAC_TEST_CANONICAL_BUNDLE/Contents/Resources/metadata/owner-sentinel" ]] || exit 43
python3 "$POB_MAC_TEST_BUNDLE_FACTORY" "$repo_root/.state/macos/current-version.json" "$POB_MAC_BUNDLE_PATH" "$POB_MAC_TEST_RUN_LOG"
printf '%s\n' bundle >> "$POB_MAC_TEST_RUN_LOG"
SH
  chmod +x "$root/scripts/mac-bundle.sh"
  cp "$REPO_ROOT/scripts/mac-smoke-test.sh" "$root/scripts/mac-smoke-test.sh"

  printf 'preserve me\n' > "$root/.cache/macos/downloads/vendor/preserved-cache-marker"
}

make_origin_repo() {
  local root="$1"
  local name="$2"
  local old_tag="$3"
  local new_tag="$4"
  local old_marker="$5"
  local new_marker="$6"
  local work="$root/origin-work/$name"
  local origin="$root/origin-bare/$name.git"

  mkdir -p "$(dirname "$work")" "$(dirname "$origin")"
  git init -q "$work"
  git -C "$work" config user.name "Native Refresh Test"
  git -C "$work" config user.email "native-refresh@example.invalid"
  printf '%s\n' "$old_marker" > "$work/source-marker"
  git -C "$work" add source-marker
  GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git -C "$work" commit -q -m old
  git -C "$work" tag -a "$old_tag" -m "$old_tag"
  printf '%s\n' "$new_marker" > "$work/source-marker"
  git -C "$work" add source-marker
  GIT_AUTHOR_DATE='2026-02-01T00:00:00Z' GIT_COMMITTER_DATE='2026-02-01T00:00:00Z' git -C "$work" commit -q -m new
  git -C "$work" tag -a "$new_tag" -m "$new_tag"
  git clone -q --bare "$work" "$origin"
  printf '%s\n' "$work"
}

seed_mirror_at_old_release() {
  local root="$1"
  local remote_url="$2"
  local mirror_name="$3"
  local old_tag="$4"
  local new_tag="$5"
  local mirror="$root/.cache/macos/git/$mirror_name.git"

  mkdir -p "$(dirname "$mirror")"
  GIT_CONFIG_GLOBAL="$root/gitconfig" git clone -q --mirror "$remote_url" "$mirror"
  git --git-dir="$mirror" update-ref -d "refs/tags/$new_tag"
  [[ "$(git --git-dir="$mirror" rev-parse --verify "refs/tags/$old_tag")" != "" ]] || exit 51
}

write_old_metadata() {
  local root="$1"
  local pob_sha="$2"
  local rusty_sha="$3"
  python3 - "$root/.state/macos/current-version.json" "$pob_sha" "$rusty_sha" <<'PY'
import json
import sys
from pathlib import Path

payload = {
    "synced_at": "2026-08-01T00:00:00Z",
    "game": "poe1",
    "version_id": "v2.67.2--v0.2.18",
    "pob": {"repo": "PathOfBuildingCommunity/PathOfBuilding", "tag": "v2.67.2", "commit": sys.argv[2], "version": "2.67.2", "published_at": "2026-08-01T00:00:00Z"},
    "rusty": {"repo": "meehl/rusty-path-of-building", "tag": "v0.2.18", "commit": sys.argv[3], "version": "0.2.18", "published_at": "2026-08-01T00:00:00Z", "minimum_required": "0.2.18"},
    "app": {"name": "Path of Building", "bundle_id": "dev.test.pathofbuilding", "support_dir": "/tmp/Path of Building"},
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

setup_fixture() {
  local root="$1"
  make_fixture_helpers "$root"
  mkdir -p "$root/home" "$root/host-builds"
  git config --file "$root/gitconfig" user.name "Native Refresh Test"
  git config --file "$root/gitconfig" user.email "native-refresh@example.invalid"

  make_origin_repo "$root" pob v2.67.2 v2.67.3 pob-old pob-new >/dev/null
  make_origin_repo "$root" rusty v0.2.18 v0.2.19 rusty-old rusty-new >/dev/null
  POB_SHA="$(git -C "$root/origin-work/pob" rev-parse 'v2.67.3^{commit}')"
  RUSTY_SHA="$(git -C "$root/origin-work/rusty" rev-parse 'v0.2.19^{commit}')"
  OLD_POB_SHA="$(git -C "$root/origin-work/pob" rev-parse 'v2.67.2^{commit}')"
  OLD_RUSTY_SHA="$(git -C "$root/origin-work/rusty" rev-parse 'v0.2.18^{commit}')"

  git config --file "$root/gitconfig" url."file://$root/origin-bare/pob.git".insteadOf https://github.com/PathOfBuildingCommunity/PathOfBuilding.git
  git config --file "$root/gitconfig" url."file://$root/origin-bare/rusty.git".insteadOf https://github.com/meehl/rusty-path-of-building.git
  seed_mirror_at_old_release "$root" https://github.com/PathOfBuildingCommunity/PathOfBuilding.git pob v2.67.2 v2.67.3
  seed_mirror_at_old_release "$root" https://github.com/meehl/rusty-path-of-building.git rusty v0.2.18 v0.2.19

  write_old_metadata "$root" "$OLD_POB_SHA" "$OLD_RUSTY_SHA"
  python3 "$root/tests/fake-bundle.py" "$root/.state/macos/current-version.json" "$root/dist/Path of Building.app" "$root/run.log"
  printf 'installed old bundle\n' > "$root/dist/Path of Building.app/Contents/Resources/metadata/owner-sentinel"
  printf 'old metadata sentinel\n' > "$root/.state/macos/metadata-sentinel"
}

run_primary() {
  local root="$1"
  shift
  (
    export HOME="$root/home"
    export PATH="$root/bin:$PATH"
    export GIT_CONFIG_GLOBAL="$root/gitconfig"
    export POB_MAC_GAME=poe1
    export POB_MAC_POB_REPO=PathOfBuildingCommunity/PathOfBuilding
    export POB_MAC_RUSTY_REPO=meehl/rusty-path-of-building
    export POB_MAC_COMPAT_REPO=meehl/rusty-pob-manifest
    export POB_MAC_RUSTY_TAG=""
    export POB_MAC_APP_NAME="Path of Building"
    export POB_BUILDS_HOST_DIR="$root/host-builds"
    export POB_MAC_SUPPORT_DIR="$root/smoke-support/Path of Building"
    export POB_MAC_BUNDLE_PATH="$root/dist/Path of Building.app"
    export POB_MAC_TEST_ROOT="$root"
    export POB_MAC_TEST_CANONICAL_BUNDLE="$root/dist/Path of Building.app"
    export POB_MAC_TEST_CURRENT_METADATA="$root/.state/macos/current-version.json"
    export POB_MAC_TEST_BUNDLE_FACTORY="$root/tests/fake-bundle.py"
    export POB_MAC_TEST_RUN_LOG="$root/run.log"
    export POB_MAC_TEST_EXPECT_CURRENT_VERSION_ID="v2.67.2--v0.2.18"
    export POB_MAC_TEST_EXPECT_POB_SHA="$POB_SHA"
    export POB_MAC_TEST_EXPECT_RUSTY_SHA="$RUSTY_SHA"
    export POB_MAC_SMOKE_TIMEOUT_SECONDS=3
    "$@" "$root/scripts/mac-refresh-primary.sh"
  )
}

assert_new_install() {
  local root="$1"
  python3 - "$root/.state/macos/current-version.json" "$root/dist/Path of Building.app/Contents/Resources/metadata/version.json" "$POB_SHA" "$RUSTY_SHA" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
bundle = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
for payload in (state, bundle):
    assert payload["pob"]["tag"] == "v2.67.3"
    assert payload["pob"]["commit"] == sys.argv[3]
    assert payload["rusty"]["tag"] == "v0.2.19"
    assert payload["rusty"]["commit"] == sys.argv[4]
    assert payload["version_id"] == "v2.67.3--v0.2.19"
assert state["pob"]["commit"] == bundle["pob"]["commit"]
assert state["rusty"]["commit"] == bundle["rusty"]["commit"]
PY
}

test_new_release_promotes_only_after_candidate_and_final_smokes() {
  local root="$1"
  run_primary "$root" env > "$root/pipeline.log"

  [[ -f "$root/.cache/macos/git/pob.git/refs/tags/v2.67.3" ]] || git --git-dir="$root/.cache/macos/git/pob.git" show-ref --verify --quiet refs/tags/v2.67.3 || fail "PoB mirror did not fetch the new release tag"
  [[ -f "$root/.cache/macos/git/rusty.git/refs/tags/v0.2.19" ]] || git --git-dir="$root/.cache/macos/git/rusty.git" show-ref --verify --quiet refs/tags/v0.2.19 || fail "Rusty mirror did not fetch the new release tag"
  assert_file_contains "$root/run.log" '^build$'
  assert_file_contains "$root/run.log" '^bundle$'
  assert_file_contains "$root/run.log" '^launch:candidate$'
  assert_file_contains "$root/run.log" '^launch:final$'
  [[ "$(grep -c '^launch:candidate$' "$root/run.log" || true)" == 1 ]] || fail "candidate launch smoke did not run exactly once"
  [[ "$(grep -c '^launch:final$' "$root/run.log" || true)" == 1 ]] || fail "installed launch smoke did not run exactly once"
  assert_file_contains "$root/pipeline.log" 'Running candidate static smoke'
  assert_file_contains "$root/pipeline.log" 'Running candidate launch smoke'
  assert_file_contains "$root/pipeline.log" 'Running final static smoke'
  assert_file_contains "$root/pipeline.log" 'Running final launch smoke'
  [[ "$(cat "$root/.state/macos/metadata-sentinel")" == 'old metadata sentinel' ]] || fail "unrelated state file changed"
  [[ -f "$root/.cache/macos/downloads/vendor/preserved-cache-marker" ]] || fail "vendor cache was removed"
  assert_new_install "$root"
  assert_no_refresh_artifacts "$root"
}

test_unchanged_release_skips_build_but_smokes_installed_bundle() {
  local root="$1"
  : > "$root/run.log"
  run_primary "$root" env POB_MAC_TEST_EXPECT_CURRENT_VERSION_ID=v2.67.3--v0.2.19 > "$root/noop.log"
  ! grep -q '^build$' "$root/run.log" || fail "unchanged release rebuilt the bundle"
  ! grep -q '^bundle$' "$root/run.log" || fail "unchanged release bundled again"
  [[ "$(grep -c '^launch:final$' "$root/run.log" || true)" == 1 ]] || fail "no-op did not launch-smoke the installed bundle"
  [[ "$(grep -c 'Native smoke test passed' "$root/noop.log" || true)" == 2 ]] || fail "no-op did not run both static and launch smoke"
  assert_file_contains "$root/noop.log" 'without rebuilding'
  assert_no_refresh_artifacts "$root"
}

test_candidate_launch_failure_never_touches_installed_bundle_or_metadata() {
  local root="$1"
  local status=0
  if run_primary "$root" env POB_MAC_TEST_FAIL_CANDIDATE_LAUNCH=1 >/dev/null 2>&1; then
    fail "candidate launch-smoke failure was ignored"
  else
    status=$?
  fi
  [[ "$status" -ne 0 ]] || fail "candidate failure returned success"
  [[ -f "$root/dist/Path of Building.app/Contents/Resources/metadata/owner-sentinel" ]] || fail "candidate failure removed installed bundle"
  [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version_id"])' "$root/.state/macos/current-version.json")" == 'v2.67.2--v0.2.18' ]] || fail "candidate failure promoted metadata"
  [[ ! -e "$root/dist/Path of Building.previous.app" ]] || fail "candidate failure created previous bundle"
  assert_no_refresh_artifacts "$root"
}

test_final_launch_failure_rolls_back_bundle_and_keeps_metadata() {
  local root="$1"
  local status=0
  if run_primary "$root" env POB_MAC_TEST_FAIL_FINAL_LAUNCH=1 >/dev/null 2>&1; then
    fail "final launch-smoke failure was ignored"
  else
    status=$?
  fi
  [[ "$status" -ne 0 ]] || fail "final smoke failure returned success"
  [[ -f "$root/dist/Path of Building.app/Contents/Resources/metadata/owner-sentinel" ]] || fail "rollback did not restore the original bundle"
  [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version_id"])' "$root/.state/macos/current-version.json")" == 'v2.67.2--v0.2.18' ]] || fail "failed final smoke promoted metadata"
  [[ ! -e "$root/dist/Path of Building.previous.app" ]] || fail "rollback left the previous bundle path behind"
  assert_no_refresh_artifacts "$root"
}

SUCCESS_ROOT=""
NOOP_ROOT=""
CANDIDATE_FAIL_ROOT=""
FINAL_FAIL_ROOT=""
cleanup() {
  for path in "$SUCCESS_ROOT" "$NOOP_ROOT" "$CANDIDATE_FAIL_ROOT" "$FINAL_FAIL_ROOT"; do
    [[ -z "$path" ]] || rm -rf "$path"
  done
}
trap cleanup EXIT

SUCCESS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pob-native-refresh-success.XXXXXX")"
NOOP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pob-native-refresh-noop.XXXXXX")"
CANDIDATE_FAIL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pob-native-refresh-candidate-fail.XXXXXX")"
FINAL_FAIL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pob-native-refresh-final-fail.XXXXXX")"

# Each fixture has independent local GitHub stand-ins, so failures and state transitions stay isolated.
for root in "$SUCCESS_ROOT" "$NOOP_ROOT" "$CANDIDATE_FAIL_ROOT" "$FINAL_FAIL_ROOT"; do
  setup_fixture "$root"
done

test_new_release_promotes_only_after_candidate_and_final_smokes "$SUCCESS_ROOT"
test_unchanged_release_skips_build_but_smokes_installed_bundle "$SUCCESS_ROOT"
test_candidate_launch_failure_never_touches_installed_bundle_or_metadata "$CANDIDATE_FAIL_ROOT"
test_final_launch_failure_rolls_back_bundle_and_keeps_metadata "$FINAL_FAIL_ROOT"

printf 'ok - mac refresh primary promotion behavior\n'
