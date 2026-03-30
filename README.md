# Path of Building Local Native Wrapper

Local macOS-native PoB builder and bundle pipeline for Apple Silicon.

The native path is source-driven:

- trigger: official `PathOfBuildingCommunity/PathOfBuilding` release tag
- runtime: compatible `meehl/rusty-path-of-building` release
- build inputs: upstream source snapshots, not the Windows portable zip

## What this repo owns

- `scripts/mac-sync-upstream.sh`: resolve the latest official PoB release and a compatible Rusty runtime, then cache both source trees
- `scripts/mac-build.sh`: build the native runtime and stage the app payload
- `scripts/mac-bundle.sh`: assemble `dist/Path of Building.app`
- `scripts/mac-launch.sh`: open the native `.app`, building it first if missing
- `scripts/mac-refresh.sh`: weekly-style sync + rebuild + bundle + smoke test
- `scripts/install-mac-refresh-agent.sh`: install the local `launchd` native refresh job
- `scripts/uninstall-mac-refresh-agent.sh`: remove that `launchd` job
- `scripts/mac-smoke-test.sh`: validate bundle structure and optionally boot the app briefly
- `macos/launcher.sh`: the bundle launcher that materializes the payload into `~/Library/Application Support/Path of Building/`

## Native First Run

```bash
./scripts/mac-sync-upstream.sh latest
./scripts/mac-build.sh
./scripts/mac-bundle.sh
./scripts/mac-launch.sh
```

The build script expects host-side Rust from `rustup` and bootstraps the C/Lua pieces with Homebrew:

- `cargo` / `rustc`
- `luajit`
- `pkgconf`
- `luarocks`

The in-app `Check for Update` path is intentionally disabled in the native macOS build.
Use the local conveyor instead:

```bash
./scripts/mac-sync-upstream.sh latest
./scripts/mac-build.sh
./scripts/mac-bundle.sh
```

The generated app lands at:

- `dist/Path of Building.app`

At runtime the app expands its mutable payload into:

- `~/Library/Application Support/Path of Building/versions/<pob-tag>--<rusty-tag>/`
- `~/Library/Application Support/Path of Building/current`
- `~/Library/Application Support/Path of Building/userdata`

Saved builds stay external:

- `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`

## Daily Use

Launch the native app:

```bash
./scripts/mac-launch.sh
```

Or double-click [POB.command](/Users/sergio/Documents/30_HOBBY_AI/POB/POB.command).

Rebuild the current native app bundle:

```bash
./scripts/mac-refresh.sh --force
```

Run a structural smoke test:

```bash
./scripts/mac-smoke-test.sh
```

Run a live launch smoke test:

```bash
./scripts/mac-smoke-test.sh --launch
```

## Weekly Native Refresh Automation

Install the local `launchd` job:

```bash
./scripts/install-mac-refresh-agent.sh
```

Defaults:

- weekday: `6` (`Saturday`)
- time: `19:00` local time
- action: check the latest official PoB release, resolve a compatible Rusty runtime, rebuild the native `.app`, and keep the previous bundle if any step fails

Override the schedule before install if needed:

```bash
POB_MAC_REFRESH_WEEKDAY=0 POB_MAC_REFRESH_HOUR=20 POB_MAC_REFRESH_MINUTE=30 ./scripts/install-mac-refresh-agent.sh
```

Remove the job:

```bash
./scripts/uninstall-mac-refresh-agent.sh
```

Logs:

- repo log: `.state/logs/mac-native-refresh.log`
- current native mapping: `.state/macos/current-version.json`
- last successful native refresh: `.state/macos/last-refresh`

## Storage Layout

- Repo-local native cache:
  - `.cache/macos/upstream/`
  - `.cache/macos/downloads/`
  - `.cache/macos/build/`
- Repo-local native state:
  - `.state/macos/current-version.json`
  - `.state/macos/last-refresh`
- Native app artifact:
  - `dist/Path of Building.app`
- Persistent host storage:
  - `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`

## Configuration

Optional overrides can be provided via environment variables or a local `.env` file:

```bash
POB_MAC_APP_NAME=Path of Building
POB_MAC_APP_BUNDLE_ID=dev.sergio.pathofbuilding.local
POB_MAC_GAME=poe1
POB_MAC_SUPPORT_DIR=/Users/sergio/Library/Application Support/Path of Building
POB_MAC_BUNDLE_PATH=/Users/sergio/Documents/30_HOBBY_AI/POB/dist/Path of Building.app
POB_MAC_RUSTY_TAG=v0.2.16
POB_MAC_REFRESH_WEEKDAY=6
POB_MAC_REFRESH_HOUR=19
POB_MAC_REFRESH_MINUTE=0
POB_BUILDS_HOST_DIR=/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds
```

See [.env.example](/Users/sergio/Documents/30_HOBBY_AI/POB/.env.example).

## Notes

- The native path rebuilds from upstream source snapshots and compatibility metadata; it does not translate the Windows binary.
- `mac-launch.sh` will trigger a full native refresh automatically if the `.app` is missing.
- The bundle launcher keeps user data outside the `.app` and only refreshes the versioned payload when the bundle version changes.
