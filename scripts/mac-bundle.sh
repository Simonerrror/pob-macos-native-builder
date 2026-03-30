#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mac-common.sh"

ensure_mac_dirs
ensure_metadata_exists

version_id="$(metadata_value '.version_id')"
stage_dir="$(native_stage_dir "$version_id")"
runtime_dir="$(native_runtime_dir "$version_id")"

if [[ ! -d "${stage_dir}/payload/current" || ! -x "${runtime_dir}/bin/rusty-path-of-building" ]]; then
  printf 'Missing native build artifacts for %s\nRun ./scripts/mac-build.sh first.\n' "$version_id" >&2
  exit 1
fi

bundle_dir="${POB_MAC_BUNDLE_PATH}"
tmp_bundle="${bundle_dir}.tmp.$$"
runtime_lib_dir="${tmp_bundle}/Contents/Resources/runtime/lib"
runtime_bin_dir="${tmp_bundle}/Contents/Resources/runtime/bin"
payload_target_dir="${tmp_bundle}/Contents/Resources/payload/current"
metadata_target_dir="${tmp_bundle}/Contents/Resources/metadata"
iconset_dir="${BUILD_ROOT}/iconset/${version_id}.iconset"

rm -rf "$tmp_bundle" "$iconset_dir"
mkdir -p \
  "${tmp_bundle}/Contents/MacOS" \
  "$runtime_lib_dir" \
  "$runtime_bin_dir" \
  "$payload_target_dir" \
  "$metadata_target_dir" \
  "$iconset_dir"

rsync -a --delete "${stage_dir}/payload/current/" "${payload_target_dir}/"
cp "${runtime_dir}/bin/rusty-path-of-building" "${runtime_bin_dir}/"
cp "${runtime_dir}/version.json" "${metadata_target_dir}/version.json"
chmod 755 "${runtime_bin_dir}/rusty-path-of-building"

bundle_deps() {
  local file="$1"
  local dep dep_name copied
  while read -r dep; do
    [[ -n "$dep" ]] || continue
    case "$dep" in
      /opt/homebrew/*|/usr/local/*)
        dep_name="$(basename "$dep")"
        copied="${runtime_lib_dir}/${dep_name}"
        if [[ ! -f "$copied" ]]; then
          cp "$dep" "$copied"
          chmod 755 "$copied"
          install_name_tool -id "@executable_path/../Resources/runtime/lib/${dep_name}" "$copied" >/dev/null 2>&1 || true
          bundle_deps "$copied"
        fi
        install_name_tool -change "$dep" "@executable_path/../Resources/runtime/lib/${dep_name}" "$file" >/dev/null 2>&1 || true
        ;;
    esac
  done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
}

bundle_deps "${runtime_bin_dir}/rusty-path-of-building"
while IFS= read -r module_file; do
  bundle_deps "$module_file"
done < <(find "${payload_target_dir}/lib" -type f \( -name '*.so' -o -name '*.dylib' \) 2>/dev/null | sort)

copy_icon_variant() {
  local size="$1"
  local output="$2"
  sips -z "$size" "$size" "${runtime_dir}/icon.png" --out "$output" >/dev/null
}

copy_icon_variant 16 "${iconset_dir}/icon_16x16.png"
copy_icon_variant 32 "${iconset_dir}/icon_16x16@2x.png"
copy_icon_variant 32 "${iconset_dir}/icon_32x32.png"
copy_icon_variant 64 "${iconset_dir}/icon_32x32@2x.png"
copy_icon_variant 128 "${iconset_dir}/icon_128x128.png"
copy_icon_variant 256 "${iconset_dir}/icon_128x128@2x.png"
copy_icon_variant 256 "${iconset_dir}/icon_256x256.png"
copy_icon_variant 512 "${iconset_dir}/icon_256x256@2x.png"
copy_icon_variant 512 "${iconset_dir}/icon_512x512.png"
copy_icon_variant 1024 "${iconset_dir}/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o "${tmp_bundle}/Contents/Resources/AppIcon.icns"

cp "${REPO_ROOT}/macos/launcher.sh" "${tmp_bundle}/Contents/MacOS/${POB_MAC_APP_NAME}"
chmod 755 "${tmp_bundle}/Contents/MacOS/${POB_MAC_APP_NAME}"

python3 - "$POB_MAC_APP_NAME" "$POB_MAC_APP_BUNDLE_ID" "$tmp_bundle/Contents/Info.plist" "${metadata_target_dir}/version.json" <<'PY'
import json
import plistlib
import sys

app_name, bundle_id, output, metadata_path = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as handle:
    version_json = json.load(handle)

payload = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleDisplayName": app_name,
    "CFBundleExecutable": app_name,
    "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": bundle_id,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": app_name,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version_json["pob"]["version"],
    "CFBundleVersion": version_json["version_id"],
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
}

with open(output, "wb") as handle:
    plistlib.dump(payload, handle, sort_keys=True)
PY

plutil -lint "${tmp_bundle}/Contents/Info.plist" >/dev/null

rm -rf "$bundle_dir"
mv "$tmp_bundle" "$bundle_dir"

log "Bundled native app: ${bundle_dir}"
