# Handoff: golden Lima/nspawn image (arm64) — the setup cascade is pre-baked

The golden image pre-runs Hydrogen Desktop's setup cascade at image-build time,
so the macOS runtime cascade reduces to machine/user-specific steps.

Built from `adom-inc/hd-lima-image` (public repo), hosted as a GitHub Release
asset. macOS sibling of `adom-inc/hd-wsl2-image` (the x86-64/WSL image).

## Current release (arm64)

- **Version:** `v8-arm64`
- **URL:** https://github.com/adom-inc/hd-lima-image/releases/download/v8/adom-golden-v8-arm64.tar.gz
- **SHA256:** `78b56e1781b445cac4aba4951074b1fbfb13c991e2a1db414572325e0aa72a02`

Pin all three in `hd-app/src/runtime/macos.rs` (`TARBALL_URL`, `TARBALL_SHA256`,
`TARBALL_VERSION`).

## What's different from the WSL image

- **arm64 Rosetta-hybrid:** native arm64 (code-server/node/claude) + x86-64
  multiarch glibc (`dpkg --add-architecture amd64` + `libc6:amd64` …) so x86-64
  Adom CLIs run translated. Rosetta itself is provided by the Lima `vz` VM (not
  baked into the rootfs).
- **Runtime = systemd-nspawn machine** `Adom-Workspace`, imported with
  `machinectl import-tar` and booted with `systemd-nspawn --boot` inside an
  HD-owned Lima utility VM `hd-builder`. No WSL, **no `/etc/wsl.conf`** — nspawn
  boots systemd as PID 1 directly.
- **No WSL DefaultUid dance:** the `adom` user (uid 1001) + sudoers + systemd
  linger are baked; nsenter execs as 1001 (`runtime/macos.rs dexec`), so there's
  no registry default-user problem to work around.
- **Host networking:** the workspace reaches the Mac via the **`adom-host`**
  alias (vz does not mirror loopback), written per machine-start by
  `init-host-internal.sh` / `runtime/macos.rs init_host_alias`.
- **Skills buckets:** `shared` + **`machine`** (not `shared` + `wsl2`).

## Baked vs runtime

Baked: apt baseline, x86-64 multiarch, code-server (+ dark theme, trusted-domains
patch, chat/UI disables, no model pin), claude CLI, Claude Code + adom-vscode
extensions, HD `shared`+`machine` skills, the adompkg-managed adom skills
(`adom/hd-mac-bootstrap`), the Adom wiki CLIs, adom-desktop CLI, adompkg, the
in-machine workspace-updater daemon + timer, `adom` user 1001 + sudoers + linger.

Runtime: `machinectl import-tar` + boot + code-server start, `set-env-vars` (live
proxy port), `inject-api-key` (Carbon token), relay start + tests, `claude-auth`
(user OAuth), `welcome`, and the per-start `adom-host` alias.

## CI

`.github/workflows/build.yml` (arm64 runner `ubuntu-24.04-arm`) builds via
`image/Dockerfile`, smoke-tests, releases the `adom-golden-<ver>-arm64.tar.gz`
asset, and pushes a single-layer image to `ghcr.io/adom-inc/hd-lima-image`.
`scripts/build-rootfs.sh` is the docker-less (chroot) translation — keep the two
in lockstep.
