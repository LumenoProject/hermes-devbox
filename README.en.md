# Hermes Devbox

[简体中文](README.md)

> [!WARNING]
> This project contains AI-generated content. Review it before use.

A customized [Hermes Agent](https://github.com/NousResearch/hermes-agent)
environment: a derived image built on the official `nousresearch/hermes-agent:stable`
(Debian 13) that adds Go, Rust, Blender LTS, GitHub CLI, uv, and common
system/networking tools, while fully preserving the upstream s6 supervision tree,
the `hermes` runtime user (UID 10000), and the `/opt/data` data-directory contract.

The base image already ships Python 3.14, Node.js 26 (npm / npx / pnpm), the
uv-managed runtime environment, Git, ripgrep, FFmpeg, Chromium, tmux,
gcc / g++ / make / cmake, and the Docker CLI.

## Quick start

```bash
# First time: build (or pull) the image and run the setup wizard
# (API keys / messaging platforms)
docker compose run --rm hermes setup

# Persistent gateway (Telegram / Discord / Slack ...), supervised by s6
docker compose up -d

# Get inside
docker compose exec hermes hermes     # interactive CLI
docker compose exec hermes bash       # shell (full devbox toolchain)
```

All Hermes state (`.env`, `config.yaml`, SOUL.md, sessions, memories, skills,
cron, logs) lives in `/opt/data`, backed by the named volume `data`, so image
upgrades never touch it. Upstream strongly recommends a named volume over
cross-VM bind mounts (the latter silently corrupt SQLite WAL databases — see
“Filesystem requirements for state.db” in the official Docker docs).

> [!IMPORTANT]
> - Do not set `init: true` or override `entrypoint:` in Compose — s6 must own
>   PID 1, otherwise supervision and zombie reaping are lost.
> - Do not run the gateway as root (the official image refuses by default).
> - Never point two gateway containers at the same data directory.

## Optional service ports

No ports are published by default. Uncomment the matching `environment` and
`ports` entries in `compose.yaml` as needed:

| Port | Service | Requirements |
|---|---|---|
| 8642 | Gateway's OpenAI-compatible API server | `API_SERVER_ENABLED=true`; `API_SERVER_KEY` is mandatory for any non-localhost exposure |
| 9119 | Web dashboard | `HERMES_DASHBOARD=1`; a non-loopback bind requires an auth provider (e.g. `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD`) |

Copy `.env.example` to `.env` to manage these variables. Read the upstream
security docs before exposing anything to the internet (an unauthenticated
dashboard was actively exploited in June 2026).

## Upgrading

```bash
docker compose build --pull     # rebuild against the newest stable base image
docker compose up -d --force-recreate
```

The data volume is preserved; the container runs config-schema migrations at
boot (with timestamped backups of `config.yaml` / `.env` first).

## Local build

```bash
docker build --pull -t hermes-devbox:local .
HERMES_IMAGE=hermes-devbox:local docker compose up -d --pull never
```

The base image can be pinned via a build arg (a digest pin is exact):

```bash
docker build --build-arg HERMES_IMAGE=nousresearch/hermes-agent:stable -t hermes-devbox:local .
```

## Added tools

| Tool | Source | Location |
|---|---|---|
| Go (latest stable) | go.dev official JSON API + SHA256 verification | `/usr/local/go` |
| Rust (stable, rustup) | official sh.rustup.rs script | `/opt/rustup`, `/opt/rust-cargo` (world read-only) |
| Blender LTS | official download.blender.org tarball + SHA256 | `/opt/blender` |
| GitHub CLI | official cli.github.com apt repository | apt |
| uv (latest stable) | official astral.sh installer | `/usr/local/bin/uv`, `uvx` |
| Networking | Debian apt | ping / traceroute(tracert) / mtr / telnet / dig / nc / tcpdump / iperf3 etc. |
| Misc | Debian apt | gh / jq / vim / nano / htop / btop / nvtop / sudo / build-essential |

Customization rules (aligned with upstream docs):

- Never clobber the PM-managed symlinks in `/usr/local/bin` (`python3`, `node`,
  `npm`, `npx`, `pnpm`, `ffmpeg`, `rg`).
- No uv-managed CPython is preinstalled, so the official `python3` is never
  shadowed; run `uv python install <version>` as the runtime user if you need
  another Python.
- `/opt/hermes` stays immutable; bake additional system tools into the
  Dockerfile instead of installing them at runtime.

## CI

GitHub Actions (`.github/workflows/docker.yml`) builds the derived image on
push / PR / weekly schedule, verifies the Hermes entrypoint chain, the devbox
toolchain, and runtime-user permissions inside a container, then publishes to
`ghcr.io/<owner>/<repo>` (the image name follows the repository name).

## License

MIT — see [LICENSE](LICENSE). Hermes Agent itself is an MIT-licensed project by
Nous Research; this repository is a derived environment and does not modify
upstream code.
