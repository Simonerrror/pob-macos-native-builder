#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

ensure_mac_dirs
ensure_metadata_exists
ensure_host_build_dependencies

pob_tag="$(metadata_value '.pob.tag')"
rusty_tag="$(metadata_value '.rusty.tag')"
version_id="$(metadata_value '.version_id')"

rusty_source_dir="${UPSTREAM_ROOT}/rusty/${rusty_tag}"
pob_source_dir="${UPSTREAM_ROOT}/pob/${pob_tag}"
stage_dir="$(native_stage_dir "$version_id")"
runtime_dir="$(native_runtime_dir "$version_id")"
downloads_vendor_dir="${DOWNLOADS_ROOT}/vendor"

if [[ ! -d "$rusty_source_dir" || ! -d "$pob_source_dir" ]]; then
  printf 'Missing upstream sources for %s / %s\nRun ./scripts/mac-sync-upstream.sh latest first.\n' "$pob_tag" "$rusty_tag" >&2
  exit 1
fi

python3 - "$stage_dir" "$runtime_dir" <<'PY'
from pathlib import Path
import subprocess
import shutil
import sys

def nuke(path: Path) -> None:
    for _ in range(3):
        if not path.exists():
            return
        for junk in path.rglob(".DS_Store"):
            junk.unlink(missing_ok=True)
        shutil.rmtree(path, ignore_errors=True)
        if not path.exists():
            return
        subprocess.run(["/bin/chmod", "-R", "u+w", str(path)], check=False)
        subprocess.run(["/bin/rm", "-rf", str(path)], check=False)
    if path.exists():
        raise SystemExit(f"Failed to remove build path: {path}")

for raw in sys.argv[1:]:
    path = Path(raw)
    nuke(path)
PY
mkdir -p "$stage_dir" "$runtime_dir" "$downloads_vendor_dir"

payload_dir="${stage_dir}/payload/current"
mkdir -p "$payload_dir"

log "Staging PoB sources into payload"
rsync -a --delete "${pob_source_dir}/src/" "${payload_dir}/"
rsync -a --delete "${rusty_source_dir}/lua/" "${payload_dir}/lua/"
mkdir -p "${payload_dir}/lib/lua/5.1"

luajit_root="$(luajit_prefix)"
if [[ -f "${HOME}/.cargo/env" ]]; then
  # Prefer rustup-managed toolchains over the heavy Homebrew rust formula.
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PKG_CONFIG_PATH="${luajit_root}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LUAJIT_LIB_DIR="${luajit_root}/lib"
export LUAJIT_INCLUDE_DIR="${luajit_root}/include/luajit-2.1"
export CARGO_HTTP_TIMEOUT="${CARGO_HTTP_TIMEOUT:-600}"
export CARGO_NET_RETRY="${CARGO_NET_RETRY:-10}"
export CARGO_REGISTRIES_CRATES_IO_PROTOCOL="${CARGO_REGISTRIES_CRATES_IO_PROTOCOL:-sparse}"

log "Applying local macOS cargo patch set"
python3 - "${rusty_source_dir}/Cargo.toml" "${rusty_source_dir}/src/clipboard.rs" <<'PY'
from pathlib import Path
import sys

manifest = Path(sys.argv[1])
clipboard = Path(sys.argv[2])

text = manifest.read_text(encoding="utf-8")
old = "[target.'cfg(unix)'.dependencies]"
new = "[target.'cfg(all(unix, not(target_os = \"macos\")))'.dependencies]"
wgpu_old = 'wgpu = { version = "27.0.1", default-features = false, features = ["std", "parking_lot", "vulkan", "wgsl"] }'
wgpu_new = 'wgpu = { version = "27.0.1", default-features = false, features = ["std", "parking_lot", "vulkan", "metal", "wgsl"] }'

if old in text and new not in text:
    text = text.replace(old, new, 1)
if wgpu_old in text and wgpu_new not in text:
    text = text.replace(wgpu_old, wgpu_new, 1)
    manifest.write_text(text, encoding="utf-8")

text = clipboard.read_text(encoding="utf-8")
text = text.replace('#[cfg(target_family = "unix")]', '#[cfg(all(target_family = "unix", not(target_os = "macos")))]')
clipboard.write_text(text, encoding="utf-8")
PY

log "Applying local macOS payload patch set"
python3 - "${payload_dir}/Launch.lua" "${payload_dir}/Modules/Main.lua" <<'PY'
from pathlib import Path
import sys

launch = Path(sys.argv[1])
main = Path(sys.argv[2])

launch_text = launch.read_text(encoding="utf-8")
launch_old = """function launch:CheckForUpdate(inBackground)
\tif self.updateCheckRunning then
\t\treturn
\tend
\tself.updateCheckBackground = inBackground
\tself.updateMsg = "Initialising..."
\tself.updateProgress = "Checking..."
\tself.lastUpdateCheck = GetTime()
\tlocal update = io.open("UpdateCheck.lua", "r")
\tlocal id = LaunchSubScript(update:read("*a"), "GetScriptPath,GetRuntimePath,GetWorkDir,MakeDir", "ConPrintf,UpdateProgress", self.connectionProtocol, self.proxyURL, self.noSSL or false)
\tif id then
\t\tself.subScripts[id] = {
\t\t\ttype = "UPDATE"
\t\t}
\t\tself.updateCheckRunning = true
\tend
\tupdate:close()
end"""
launch_new = """function launch:CheckForUpdate(inBackground)
\tself.updateCheckRunning = false
\tself.updateAvailable = nil
\tself.updateProgress = "Managed externally"
\tself.lastUpdateCheck = GetTime()
\tif not inBackground then
\t\tself:ShowPrompt(1, 0.85, 0.2, "^8Updates are managed externally in the native macOS build.\\n\\n^0Use the local conveyor or scheduled refresh job to pull new upstream releases.")
\tend
\tConPrintf("In-app update is disabled for the native macOS build.")
\treturn "external"
end"""
if launch_old in launch_text and launch_new not in launch_text:
    launch_text = launch_text.replace(launch_old, launch_new, 1)
launch.write_text(launch_text, encoding="utf-8")

main_text = main.read_text(encoding="utf-8")
main_text = main_text.replace(
    'return launch.updateCheckRunning and launch.updateProgress or "Check for Update"',
    'return launch.updateCheckRunning and launch.updateProgress or "Update via Conveyor"',
)
main.write_text(main_text, encoding="utf-8")
PY

log "Building lzip native module"
(
  cd "${rusty_source_dir}/lua/libs/lzip"
  make clean >/dev/null 2>&1 || true
  make DESTDIR="${payload_dir}" LUA_CMOD=/lib/lua/5.1 LUA_IMPL=luajit install
)

dkjson_rock="${downloads_vendor_dir}/dkjson-2.8-1.src.rock"
luautf8_rock="${downloads_vendor_dir}/luautf8-0.1.6-1.src.rock"
luasocket_rock="${downloads_vendor_dir}/luasocket-3.1.0-1.src.rock"
luacurl_tar="${downloads_vendor_dir}/Lua-cURLv3-v0.3.13.tar.gz"

download_with_sha256 "https://luarocks.org/manifests/dhkolf/dkjson-2.8-1.src.rock" "$dkjson_rock" "$POB_MAC_DKJSON_SHA256"
download_with_sha256 "https://luarocks.org/manifests/xavier-wang/luautf8-0.1.6-1.src.rock" "$luautf8_rock" "$POB_MAC_LUAUTF8_SHA256"
download_with_sha256 "https://luarocks.org/manifests/lunarmodules/luasocket-3.1.0-1.src.rock" "$luasocket_rock" "$POB_MAC_LUASOCKET_SHA256"
download_with_sha256 "https://github.com/Lua-cURL/Lua-cURLv3/archive/refs/tags/v0.3.13.tar.gz" "$luacurl_tar" "$POB_MAC_LUACURL_SHA256"

log "Installing Lua rocks into payload"
luarocks --tree="${payload_dir}" --lua-dir="${luajit_root}" --lua-version=5.1 build "$dkjson_rock"
luarocks --tree="${payload_dir}" --lua-dir="${luajit_root}" --lua-version=5.1 build "$luautf8_rock"
luarocks --tree="${payload_dir}" --lua-dir="${luajit_root}" --lua-version=5.1 build "$luasocket_rock"

luacurl_build_dir="${BUILD_ROOT}/vendor/Lua-cURLv3"
rm -rf "$luacurl_build_dir"
mkdir -p "$luacurl_build_dir"
tar -xzf "$luacurl_tar" -C "$luacurl_build_dir" --strip-components=1

log "Building Lua-cURLv3 native module"
(
  cd "$luacurl_build_dir"
  make clean >/dev/null 2>&1 || true
  make DESTDIR="${payload_dir}" LUA_CMOD=/lib/lua/5.1 LUA_LMOD=/share/lua/5.1 LUA_IMPL=luajit install
)

log "Building rusty-path-of-building binary"
(
  cd "$rusty_source_dir"
  cargo build --release
)

mkdir -p "${runtime_dir}/bin" "${runtime_dir}/lib"
cp "${rusty_source_dir}/target/release/rusty-path-of-building" "${runtime_dir}/bin/"
chmod 755 "${runtime_dir}/bin/rusty-path-of-building"
cp "${rusty_source_dir}/assets/icon.png" "${runtime_dir}/icon.png"
cp "$VERSION_METADATA_FILE" "${runtime_dir}/version.json"

log "Native build complete for ${version_id}"
