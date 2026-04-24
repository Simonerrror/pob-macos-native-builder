# Path of Building macOS Native Build Conveyor

Unofficial source-only macOS build pipeline for running
[Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding)
with the [Rusty Path of Building](https://github.com/meehl/rusty-path-of-building)
runtime on Apple Silicon.

This repository does not publish a ready-made `.app`. It publishes the recipe and
checks that let each user build, sign, and run their own local app bundle.

## Give This To Your Agent

Paste this into Codex, Claude Code, or another local coding agent from a fresh
clone on an Apple Silicon Mac:

```text
Build Path of Building for macOS from this repository.

Requirements:
- Do not download or trust a prebuilt macOS app bundle.
- Use the repository scripts to sync upstream source, build the native runtime,
  assemble the local app bundle, and run both smoke tests.
- Keep generated artifacts local: dist/, .cache/, .state/, and .env must not be
  committed.
- If a dependency, upstream tag, or signing choice is unclear, stop and report
  exact versions/commands instead of guessing.

Run:
./scripts/mac-sync-upstream.sh latest
./scripts/mac-build.sh
./scripts/mac-bundle.sh
./scripts/mac-smoke-test.sh
./scripts/mac-smoke-test.sh --launch

Then report the final bundle path, PoB version, Rusty PoB version, and whether
the launched app materialized the same bundle-sync-stamp as the bundle metadata.
```

The final local bundle is:

- `dist/Path of Building.app`

## What This Is

The official Path of Building Community project ships downloads from its
[Releases](https://github.com/PathOfBuildingCommunity/PathOfBuilding/releases)
page and official website. This repo is not a fork of that app, not an upstream
replacement, and not a binary distribution channel.

It is a small macOS conveyor that:

- resolves an official PoB release tag
- resolves a compatible Rusty PoB release
- builds the Rust runtime locally
- stages the upstream Lua/assets payload from source snapshots
- assembles a local `.app` bundle
- materializes mutable runtime data outside the app bundle
- disables PoB's in-app update path in favor of repeatable local rebuilds

## Why Source-Only

macOS app bundles carry local trust decisions: code signing identity,
Gatekeeper/quarantine state, notarization choices, and bundled native libraries.
Those decisions should happen on the user's machine, not be hidden inside a
random uploaded zip.

For that reason:

- `dist/Path of Building.app` is ignored
- `.cache/` and `.state/` are ignored
- release uploads should contain source or notes only, not a prebuilt app
- users who want distribution signing should use their own Apple Developer ID

The default bundle step uses ad-hoc signing only, enough for local execution and
smoke testing.

## Manual Build

Install host tools first:

- Xcode command line tools
- Homebrew
- Rust via `rustup`

Then run:

```bash
./scripts/mac-sync-upstream.sh latest
./scripts/mac-build.sh
./scripts/mac-bundle.sh
./scripts/mac-smoke-test.sh
./scripts/mac-smoke-test.sh --launch
```

Launch the app:

```bash
./scripts/mac-launch.sh
```

If the `.app` is missing, `mac-launch.sh` triggers a full native refresh.

## What This Repo Owns

- `scripts/mac-sync-upstream.sh`: resolve and cache upstream source snapshots
- `scripts/mac-build.sh`: build Rusty PoB and stage the PoB payload
- `scripts/mac-bundle.sh`: assemble `dist/Path of Building.app`
- `scripts/mac-smoke-test.sh`: validate bundle structure and live launch state
- `scripts/mac-refresh.sh`: sync, build, bundle, and smoke test in one command
- `scripts/install-mac-refresh-agent.sh`: install a local `launchd` refresh job
- `scripts/uninstall-mac-refresh-agent.sh`: remove that refresh job
- `scripts/install-macos-launcher.sh`: install a Desktop launcher
- `macos/launcher.sh`: materialize the payload into app support and start Rusty PoB

## Runtime Layout

At runtime the launcher expands the immutable bundle payload into app support:

- `~/Library/Application Support/Path of Building/versions/<pob-tag>--<rusty-tag>/`
- `~/Library/Application Support/Path of Building/current`
- `~/Library/Application Support/Path of Building/userdata`
- `~/Library/Application Support/RustyPathOfBuilding1/`

Saved builds default to:

- `~/Documents/Path of Building/Builds`

Override this with `POB_BUILDS_HOST_DIR` if you already keep builds elsewhere.

## Configuration

Optional overrides can be exported in the shell or placed in a local `.env`
file. The `.env` file is ignored by git and loaded by the scripts before
defaults are applied.

```bash
POB_MAC_APP_NAME="Path of Building"
POB_MAC_APP_BUNDLE_ID=dev.local.pathofbuilding.macos
POB_MAC_GAME=poe1
POB_MAC_SUPPORT_DIR="$HOME/Library/Application Support/Path of Building"
POB_MAC_BUNDLE_PATH="$PWD/dist/Path of Building.app"
POB_MAC_RUSTY_TAG=v0.2.16
POB_MAC_REFRESH_WEEKDAY=6
POB_MAC_REFRESH_HOUR=19
POB_MAC_REFRESH_MINUTE=0
POB_MAC_REFRESH_AGENT_LABEL=dev.local.pathofbuilding.mac-native-refresh
POB_BUILDS_HOST_DIR="$HOME/Documents/Path of Building/Builds"
```

See [.env.example](.env.example).

## Refresh Automation

Install the local weekly `launchd` job:

```bash
./scripts/install-mac-refresh-agent.sh
```

Defaults:

- weekday: `6` (`Saturday`)
- time: `19:00` local time
- action: check latest official PoB release, resolve compatible Rusty PoB,
  rebuild the local `.app`, then keep the previous bundle if any step fails

Override the schedule before install:

```bash
POB_MAC_REFRESH_WEEKDAY=0 POB_MAC_REFRESH_HOUR=20 POB_MAC_REFRESH_MINUTE=30 ./scripts/install-mac-refresh-agent.sh
```

Remove the job:

```bash
./scripts/uninstall-mac-refresh-agent.sh
```

## Publishing Checklist

Before pushing this repository:

```bash
git status --short --ignored
./scripts/mac-smoke-test.sh
./scripts/mac-smoke-test.sh --launch
```

Check that no generated files are staged:

- no `dist/`
- no `.cache/`
- no `.state/`
- no `.env`
- no local `AGENTS.md`

GitHub Releases, if used, should describe the tested upstream versions and
build procedure. They should not attach `Path of Building.app.zip`.

## Upstream And Related Work

- [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding):
  official community-maintained PoB source and releases.
- [Path of Building Community website](https://pathofbuilding.community/):
  official download and project landing page.
- [Rusty Path of Building](https://github.com/meehl/rusty-path-of-building):
  Rust runtime used here. Its primary goal is native Linux support, with
  cross-platform runtime architecture.
- [PoBFrontend](https://github.com/hsource/pobfrontend):
  older cross-platform driver with macOS build notes.
- [AUR rusty-path-of-building](https://aur.archlinux.org/packages/rusty-path-of-building):
  Linux packaging example for Rusty PoB.

## License

This repository's scripts and documentation are MIT licensed. Upstream Path of
Building Community, Rusty Path of Building, Lua libraries, and bundled native
dependencies remain under their own licenses.
