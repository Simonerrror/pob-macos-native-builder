# Path of Building Local OrbStack Wrapper

Local flatpak-native PoB runner for OrbStack on macOS.

The repo now owns one runtime path only:

- `flatpak-native`: Linux-native build based on the current Flathub approach with `rusty-path-of-building`

The GUI is exposed through `xrdp` for `Windows App` on macOS.

## What this repo owns

- `Dockerfile.flatpak.builder`: isolated Flatpak builder image
- `Dockerfile.flatpak.runner` + `docker-compose.flatpak.yml`: lean Flatpak runtime + `xrdp` stack
- `flatpak/community.pathofbuilding.PathOfBuilding.yml`: local Flatpak manifest used for build/export
- `scripts/flatpak-sync-upstream.sh`: pull the latest upstream Flathub manifest and regenerate the local manifest
- `scripts/flatpak-bootstrap.sh`: install Freedesktop runtime and SDK into repo-local Flatpak state
- `scripts/flatpak-build.sh`: build and export the local Flatpak repo
- `scripts/flatpak-run.sh`: recreate the runtime container
- `scripts/flatpak-refresh.sh`: weekly-style sync + rebuild + optional runner restart
- `scripts/install-flatpak-refresh-agent.sh`: install the local `launchd` rebuild job
- `scripts/uninstall-flatpak-refresh-agent.sh`: remove that `launchd` job
- RDP entrypoint: `localhost:3389`
- Persistent user data on macOS:
  - builds: `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`

## What this repo does not own

- No Wine path
- No official Windows portable zip mirror
- No Windows VM
- No Windows containers

## First Run

```bash
./scripts/flatpak-sync-upstream.sh latest
./scripts/flatpak-bootstrap.sh
./scripts/flatpak-build.sh
./scripts/up.sh
```

Open `Windows App` on macOS and add a new PC:

- address: `localhost:3389`
- username: `root`
- password: value of `POB_RDP_PASSWORD`
- keep the macOS input source on `ABC`/English unless you explicitly change `POB_RDP_KEYLAYOUT`

## Daily Use

Bring the stack up:

```bash
./scripts/up.sh
```

Stop it:

```bash
./scripts/down.sh
```

Tail logs:

```bash
./scripts/logs.sh
```

Open a debug shell in the builder image:

```bash
./scripts/flatpak-shell.sh
```

Open a debug shell in the runtime image:

```bash
./scripts/flatpak-shell.sh runner
```

## Upstream Patch Flow

Pull the latest Flathub-side changes into the local manifest:

```bash
./scripts/flatpak-sync-upstream.sh latest
```

Build and export the local Flatpak repo:

```bash
./scripts/flatpak-build.sh
```

One-shot refresh with rebuild and runner recreate:

```bash
./scripts/flatpak-refresh.sh
```

Force rebuild even if the upstream snapshot did not change:

```bash
./scripts/flatpak-refresh.sh --force
```

Refresh without restarting the running RDP container:

```bash
./scripts/flatpak-refresh.sh --no-restart
```

## Weekly Rebuild Automation

Install the local `launchd` job:

```bash
./scripts/install-flatpak-refresh-agent.sh
```

Defaults:

- weekday: `6` (`Saturday`)
- time: `19:00` local time
- action: check latest Flathub snapshot, sync local manifest, rebuild, and recreate the runner on success

Override the schedule before install if needed:

```bash
POB_FLATPAK_REFRESH_WEEKDAY=0 POB_FLATPAK_REFRESH_HOUR=20 POB_FLATPAK_REFRESH_MINUTE=30 ./scripts/install-flatpak-refresh-agent.sh
```

Remove the job:

```bash
./scripts/uninstall-flatpak-refresh-agent.sh
```

Logs:

- repo log: `.state/logs/flatpak-refresh.log`
- last applied upstream snapshot: `.state/flatpak-upstream-head`
- last successful refresh timestamp: `.state/flatpak-upstream-last-refresh`

## Storage Layout

- Repo-local Flatpak cache:
  - `.cache/flatpak/upstream/`
  - `.cache/flatpak/build/`
  - `.cache/flatpak/repo/`
  - `.cache/flatpak/state/`
- Persistent host storage:
  - `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`

Inside the container, the build directory is mounted at `/data/builds`. The runtime links that directory into both `Path of Building*` and `RustyPathOfBuilding*` app-data roots so saved builds survive container recreation.

## Configuration

Optional overrides can be provided via environment variables or a local `.env` file:

```bash
POB_DOCKER_CONTEXT=orbstack
POB_RDP_PASSWORD=changeme
POB_RDP_PORT=3389
POB_RDP_KEYLAYOUT=0x00000409
POB_FLATPAK_BUILDER_IMAGE=pob-flatpak-builder:local
POB_FLATPAK_RUNNER_IMAGE=pob-flatpak-runner:local
POB_FLATPAK_RDP_PORT=3389
POB_FLATPAK_APP_ID=community.pathofbuilding.PathOfBuilding
POB_FLATPAK_GAME=poe1
POB_FLATPAK_RUNTIME_VERSION=25.08
POB_FLATPAK_UPSTREAM_SNAPSHOT=aa186a1606107b3f9035ea03d72c79e8ea24c885
POB_FLATPAK_REFRESH_WEEKDAY=6
POB_FLATPAK_REFRESH_HOUR=19
POB_FLATPAK_REFRESH_MINUTE=0
POB_BUILDS_HOST_DIR=/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds
```

See [.env.example](/Users/sergio/Documents/30_HOBBY_AI/POB/.env.example).

## Notes

- `docker-compose.flatpak.yml` no longer uses full `privileged`; the runtime now runs with `SYS_ADMIN` plus `seccomp=unconfined`, which is enough for local `bubblewrap`-based Flatpak execution in this setup.
- The repo now splits Flatpak concerns into two images: a heavier builder and a leaner runtime. Repeated rebuilds should be cheaper when you avoid `--no-cache`.
- `flatpak-sync-upstream.sh` regenerates the local manifest from the latest upstream Flathub manifest and removes the `extrafiles` packaging block that is not needed for this local runner.
- `scripts/up.sh`, `scripts/down.sh`, and `scripts/logs.sh` now target the Flatpak stack only.
- `flatpak-run.sh` and `up.sh` both default to `localhost:3389`; do not run another RDP stack on the same port at the same time.
- The runtime starts `rusty-path-of-building` with `POB_FLATPAK_GAME=poe1` by default. Switch it to `poe2` if you want the PoE 2 asset set instead.
