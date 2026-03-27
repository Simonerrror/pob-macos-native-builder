# Path of Building Local OrbStack Wrapper

Local wrapper repo for two PoB runtime paths on OrbStack:

- `flatpak-native`: Linux-native build based on the current Flathub approach with `rusty-path-of-building`
- `wine-fallback`: official `Path of Building Community` portable release under `Wine`

Both paths expose the GUI through `xrdp` for `Windows App` on macOS.

## What this repo owns

- `scripts/sync-release.sh`: download and extract the official PoB portable release into repo-local cache
- `docker-compose.yml` + `Dockerfile`: build and run the `Wine` + `xrdp` stack
- `docker-compose.flatpak.yml` + `Dockerfile.flatpak`: build and run the `Flatpak` + `xrdp` stack
- `flatpak/community.pathofbuilding.PathOfBuilding.yml`: local Flatpak manifest fork for the native Linux path
- RDP entrypoint: `localhost:3389`
- Persistent user data on macOS:
  - builds: `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`
  - wine prefix: `/Users/sergio/Documents/30_HOBBY_AI/POB-data/wine-prefix`

## What this repo does not own

- No Windows VM
- No Windows containers
- No full upstream source mirror for Path of Building Community

## Runtime paths

Flatpak-native path:

- build helper image: `Dockerfile.flatpak`
- local manifest: `flatpak/community.pathofbuilding.PathOfBuilding.yml`
- scripts:
  - `./scripts/flatpak-bootstrap.sh`
  - `./scripts/flatpak-build.sh`
  - `./scripts/flatpak-run.sh`
  - `./scripts/flatpak-shell.sh`

Wine fallback path:

- official portable zip + `Wine`
- scripts:
  - `./scripts/sync-release.sh latest`
  - `./scripts/up.sh`
  - `./scripts/down.sh`
  - `./scripts/logs.sh`

## Prerequisites

- OrbStack or another Docker engine available on macOS
- Enough disk space for:
  - PoB portable archive: about 500 MB
  - extracted runtime: about 500 MB
  - Docker image layers and Wine prefix

## Flatpak-native first run

```bash
./scripts/flatpak-bootstrap.sh
./scripts/flatpak-build.sh
./scripts/flatpak-run.sh
```

Open `Windows App` on macOS and add a new PC:

- address: `localhost:3389`
- username: `root`
- password: value of `POB_RDP_PASSWORD`
- keep the macOS input source on `ABC`/English for the RDP session unless you explicitly change `POB_RDP_KEYLAYOUT`

## Wine fallback first run

```bash
./scripts/sync-release.sh latest
./scripts/ensure-base-image.sh
./scripts/up.sh
```

Open `Windows App` on macOS and add a new PC:

- address: `localhost:3389`
- username: `root`
- password: value of `POB_RDP_PASSWORD`
- keep the macOS input source on `ABC`/English for the RDP session unless you explicitly change `POB_RDP_KEYLAYOUT`

## Release Prefetch Automation

You can install a local `launchd` job that checks for the latest official PoB release after working hours, downloads it into cache, and extracts it without switching the active runtime.

Install the job:

```bash
./scripts/install-release-prefetch-agent.sh
```

Default schedule is daily at `18:30` local time. Override it before install if needed:

```bash
POB_PREFETCH_HOUR=19 POB_PREFETCH_MINUTE=15 ./scripts/install-release-prefetch-agent.sh
```

Manual prefetch run:

```bash
./scripts/prefetch-latest.sh
```

Remove the job:

```bash
./scripts/uninstall-release-prefetch-agent.sh
```

## Operations

Flatpak bootstrap:

```bash
./scripts/flatpak-bootstrap.sh
```

Build the native Flatpak app:

```bash
./scripts/flatpak-build.sh
```

Run the native Flatpak stack:

```bash
./scripts/flatpak-run.sh
```

Open a debug shell in the Flatpak helper image:

```bash
./scripts/flatpak-shell.sh
```

Download a specific Wine fallback release:

```bash
./scripts/sync-release.sh v2.63.0
```

Prefetch the latest release without making it active:

```bash
./scripts/sync-release.sh --prefetch latest
```

Bring the Wine fallback stack up:

```bash
./scripts/up.sh
```

Populate or refresh the local Docker base image cache:

```bash
./scripts/ensure-base-image.sh
```

Stop the Wine fallback stack:

```bash
./scripts/down.sh
```

Tail logs:

```bash
./scripts/logs.sh
```

You can also use plain Docker Compose directly:

```bash
docker --context orbstack compose up -d
docker --context orbstack compose down
docker --context orbstack compose logs -f
```

Flatpak stack directly:

```bash
docker --context orbstack compose -f docker-compose.flatpak.yml up -d --build
docker --context orbstack compose -f docker-compose.flatpak.yml down
docker --context orbstack compose -f docker-compose.flatpak.yml logs -f
```

## Storage layout

- Repo-local release cache:
  - `.cache/downloads/<tag>/PathOfBuildingCommunity-Portable.zip`
  - `.cache/runtime/<tag>/`
  - `.cache/runtime/current -> .cache/runtime/<tag>`
- Repo-local Docker cache:
  - `.cache/flatpak/upstream/cargo-sources.json`
  - `.cache/flatpak/build/`
  - `.cache/flatpak/repo/`
  - `.cache/flatpak/state/`
  - `.cache/images/debian-bookworm-slim.tar`
- Persistent host storage:
  - `/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds`
  - `/Users/sergio/Documents/30_HOBBY_AI/POB-data/wine-prefix`

Inside the container, the build directory is mounted at `/data/builds`. The Wine fallback links that directory into the Wine user documents path, while the Flatpak runtime links it into both `Path of Building*` and `RustyPathOfBuilding*` app-data roots so saved builds survive container recreation.

## Configuration

Optional overrides can be provided via environment variables or a local `.env` file:

```bash
POB_DOCKER_CONTEXT=orbstack
POB_RDP_PASSWORD=changeme
POB_RDP_PORT=3389
POB_RDP_KEYLAYOUT=0x00000409
POB_FLATPAK_IMAGE=pob-flatpak:local
POB_FLATPAK_RDP_PORT=3389
POB_FLATPAK_APP_ID=community.pathofbuilding.PathOfBuilding
POB_FLATPAK_GAME=poe1
POB_FLATPAK_RUNTIME_VERSION=25.08
POB_FLATPAK_UPSTREAM_SNAPSHOT=aa186a1606107b3f9035ea03d72c79e8ea24c885
POB_BUILDS_HOST_DIR=/Users/sergio/Documents/30_HOBBY_AI/POB-data/builds
POB_WINEPREFIX_HOST_DIR=/Users/sergio/Documents/30_HOBBY_AI/POB-data/wine-prefix
```

See [.env.example](/Users/sergio/Documents/30_HOBBY_AI/POB/.env.example).

## Notes

- `docker-compose.yml` pins the container to `linux/amd64`. On Apple Silicon, OrbStack emulates it.
- `docker-compose.flatpak.yml` uses a privileged helper container because local Flatpak build/run inside Docker needs `bubblewrap` and sandbox-related kernel features.
- `scripts/up.sh`, `scripts/down.sh`, and `scripts/logs.sh` prefer `POB_DOCKER_CONTEXT`, then auto-detect an `orbstack` Docker context if it exists.
- `scripts/ensure-base-image.sh` caches `debian:bookworm-slim` under `.cache/images/` and loads it locally before pulling from the network.
- `Dockerfile` uses BuildKit cache mounts for `apt`, so repeated builds reuse Debian package downloads when you avoid `--no-cache`.
- `Dockerfile.flatpak` also uses BuildKit cache mounts for `apt`; repeated helper-image rebuilds should be cheaper if you avoid `--no-cache`.
- `flatpak-bootstrap.sh` downloads a pinned `cargo-sources.json` snapshot from the Flathub PoB repo into `.cache/flatpak/upstream/`.
- `flatpak-build.sh` expects that cached `cargo-sources.json` file and exports a local Flatpak repo under `.cache/flatpak/repo/`.
- `flatpak-run.sh` defaults to `POB_FLATPAK_GAME=poe1`; switch it to `poe2` if you want the PoE 2 asset set instead.
- `flatpak-run.sh` and `scripts/up.sh` both default to `localhost:3389`; do not run both stacks at once unless you change one of the RDP ports.
- `sync-release.sh` verifies the release archive against the GitHub API `sha256` digest when available.
- `sync-release.sh --prefetch` downloads and extracts a newer release into cache without changing `.cache/runtime/current`.
- The launchd job only prefetches releases; activation still happens manually when you run `./scripts/sync-release.sh latest`.
- The GUI transport is direct `xrdp` for `Windows App`; internally the image uses an `Xvnc` session backend rather than browser-based VNC.
- By default the container forces RDP keylayout `0x00000409` to avoid broken `0x00000419` mapping in `Windows App`; set `POB_RDP_KEYLAYOUT` if you want a different layout.
