# Path of Building macOS Native Build Conveyor

Source-only instructions and scripts for building a local Apple Silicon `.app`
from [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding)
and [Rusty Path of Building](https://github.com/meehl/rusty-path-of-building).

Each refresh resolves the latest official stable PoB release and the latest
stable Rusty release satisfying its upstream compatibility manifest. The
resolved tags and commits are recorded for that run; later refreshes discover
new releases. An older calculator is not a successful substitute for an
incompatible current release.

## Give This To Your Agent

Paste this into your local coding agent from a clone on an Apple Silicon Mac:

```text
Build or update native Path of Building for macOS from this checkout.

Use ./scripts/mac-refresh-primary.sh as the installation and update process.
It resolves current official stable PoB and Rusty releases, builds a candidate,
checks it, and promotes it with rollback if final verification fails.

Requirements:
- Use the latest official stable upstream releases for the selected game.
  Do not pin an older PoB or Rusty release to make a failed update look successful.
- Prepare only missing build prerequisites, following the user's dependency policy.
- Build from source. Do not download a prebuilt macOS app.
- Preserve existing builds, settings, the installed app on failure, and reusable caches.
- Keep dist/, .cache/, .state/, .env and local AGENTS.md out of Git.
- If network access, compatibility, build or smoke verification fails, report the
  exact blocker. Repair source or scripts when possible and retry the same process.
  Do not repair the installed .app in place or silently fall back to older releases.
- Install a scheduled refresh job or Desktop launcher only when requested.

Run:
./scripts/mac-refresh-primary.sh

Report the final bundle path, selected game, PoB and Rusty tags and commits,
the bundle's macOS minimum, and the static and launch smoke results.
```

The local bundle is `dist/Path of Building.app`. PoE 1 is the default game.
Set `POB_MAC_GAME=poe2` to select the PoE 2 upstream and compatibility manifest.

## Requirements

Use an Apple Silicon Mac with Xcode command line tools, Homebrew, Rust/Cargo
(preferably via `rustup`), and Python 3. The build also uses `luajit`, `pkgconf`
and `luarocks`; the build script installs missing Homebrew formulae. The agent
must review missing dependencies under the user's applicable policy before
running the build.

Python is used during source preparation, compilation and verification. The
bundled launcher reads metadata with the system `plutil` and does not require
Python to start the app. `jq` is not required.

There is no independently imposed macOS version floor. Each new bundle derives
`LSMinimumSystemVersion` from the deployment targets of its Rusty executable
and required native libraries/modules. The chosen upstream release and local
toolchain determine those targets; do not infer support for older macOS from
the Rusty version alone.

## Build, Update And Launch

Build or check for current upstream releases:

```bash
./scripts/mac-refresh-primary.sh
```

The process uses persistent Git mirrors, resolves release tags to commits, and
builds in a temporary workspace. It runs static and launch smoke checks on the
candidate and installed bundle. If verification fails, it preserves or restores
the previous app and version metadata and exits with an error. A network or
compatibility failure is reported as a blocker, not as a successful refresh.

When releases are unchanged, it verifies the installed bundle without rebuilding.
To rebuild the current upstream releases:

```bash
./scripts/mac-refresh-primary.sh --force
```

Launch the local app:

```bash
./scripts/mac-launch.sh
```

If the app is missing, the launcher runs the primary process first. PoB's in-app
update path is disabled; use the primary process to update the native bundle.

## Runtime Data

The launcher materializes the bundle payload outside the app:

- `~/Library/Application Support/Path of Building/versions/<pob-tag>--<rusty-tag>/`
- `~/Library/Application Support/Path of Building/current`
- `~/Library/Application Support/Path of Building/userdata`
- `~/Library/Application Support/RustyPathOfBuilding1/` (or `RustyPathOfBuilding2/`)

Builds default to `~/Documents/Path of Building/Builds`. Set `POB_BUILDS_HOST_DIR`
to use an existing builds directory. User data remains separate from rebuilt apps.

## Configuration And Optional Automation

Export overrides or put them in a local, ignored `.env`. See [.env.example](.env.example).
Do not pin upstream release versions in configuration.

Install a weekly `launchd` refresh job when requested:

```bash
./scripts/install-mac-refresh-agent.sh
```

The job runs the primary process on Saturday at 19:00 local time. Override
`POB_MAC_REFRESH_WEEKDAY`, `POB_MAC_REFRESH_HOUR` and `POB_MAC_REFRESH_MINUTE`
before installation to change the schedule. Remove it with:

```bash
./scripts/uninstall-mac-refresh-agent.sh
```

## Source Distribution And Checks

Distribute this repository and the instructions. The `.app` is built and
ad-hoc signed on the recipient's Mac. Generated apps and caches stay local.

Check script behavior without building or opening the real app:

```bash
bash tests/mac-smoke-test-launch.sh
bash tests/mac-refresh-primary-test.sh
```

Check an existing local bundle:

```bash
./scripts/mac-smoke-test.sh
./scripts/mac-smoke-test.sh --launch
```

Before publishing source changes, check `git status --short --ignored` and
exclude `dist/`, `.cache/`, `.state/`, `.env` and local `AGENTS.md`.

## Upstream And Related Work

- [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding):
  calculator source, game data and releases.
- [Rusty Path of Building](https://github.com/meehl/rusty-path-of-building):
  native runtime; macOS support is included upstream.
- [Rusty's Homebrew tap](https://github.com/meehl/homebrew-rusty-path-of-building):
  installs the command-line runtime and Lua modules; it does not create a `.app`.

## License

This repository's scripts and documentation are MIT licensed. Upstream Path of
Building Community, Rusty Path of Building, Lua libraries, and native dependencies
remain under their own licenses.
