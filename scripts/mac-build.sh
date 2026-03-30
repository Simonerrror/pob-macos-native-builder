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

rm -rf "$stage_dir" "$runtime_dir"
mkdir -p "$stage_dir" "$runtime_dir" "$downloads_vendor_dir"

payload_dir="${stage_dir}/payload/current"
mkdir -p "$payload_dir"

log "Staging PoB sources into payload"
rsync -a --delete "${pob_source_dir}/src/" "${payload_dir}/"
rsync -a --delete "${rusty_source_dir}/lua/" "${payload_dir}/lua/"
mkdir -p "${payload_dir}/lib/lua/5.1"

luajit_root="$(luajit_prefix)"
export PATH="$(brew --prefix rust)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PKG_CONFIG_PATH="${luajit_root}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LUAJIT_LIB_DIR="${luajit_root}/lib"
export LUAJIT_INCLUDE_DIR="${luajit_root}/include/luajit-2.1"

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
  make DESTDIR="${payload_dir}" LUA_CMOD=/lib/lua/5.1 LUA_IMPL=luajit install
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
