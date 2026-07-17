# hd-lima-image — golden Lima/nspawn rootfs (arm64 Rosetta-hybrid) for Hydrogen Desktop on macOS

Builds the **golden image** that Hydrogen Desktop imports via
`machinectl import-tar Adom-Workspace adom-golden-<ver>-arm64.tar.gz` — booting it as
a **systemd-nspawn machine** inside an HD-owned **Lima** utility VM (`vmType: vz`,
Apple Virtualization.framework, arm64 + Rosetta).

macOS sibling of [`hd-wsl2-image`](https://github.com/adom-inc/hd-wsl2-image) (the
x86-64/WSL image). Same baked cascade; the differences are the **arm64 Rosetta-hybrid**
rootfs (native arm64 code-server/node/claude + x86-64 multiarch glibc so x86-64 Adom
CLIs run translated under Rosetta) and the **nspawn** runtime (no WSL, no `/etc/wsl.conf`).
This is a **public** image: nothing in it requires GitHub authentication, and updates
ship as new image versions (monthly bake), not git pulls.

| Baked at build (cascade step) | Left to runtime |
|---|---|
| Ubuntu 24.04 (arm64) apt baseline (build-essential, cmake, node, python3, gh, …) | `machinectl import-tar` + code-server start (step 1–2) |
| **x86-64 multiarch glibc** (`dpkg --add-architecture amd64`) so Rosetta can run x86-64 Adom binaries | Rosetta itself (provided by the Lima `vz` VM, not baked) |
| code-server (pinned) + **dark-mode settings.json + trusted-domains patch** (step 7) | layout hides via :8821 (browser-state half of step 7) |
| **adom skills** via adom-wiki (`adom-wiki pkg install adom/hd-mac-bootstrap` et al.; adompkg retired) | `set-env-vars` — live proxy port (step 5) |
| **claude CLI** at `~/.local/bin/claude` + PATH (step 15) | `inject-api-key` — Adom session token (step 6) |
| **Claude Code extension** from Open VSX (step 16) | relay start + tests (steps 9, 11–14) |
| **adom-vscode binary + extension** registered with code-server (step 3) | `claude-auth` — user OAuth (step 17) |
| **HD self-awareness skills** shared/ + machine/ (step 8) | `welcome` (step 18) |
| **adom-desktop CLI** latest published (step 10) | `adom-host` alias (per machine start) |
| Adom CLIs from the public wiki: adom-cli, adom-wiki, adom-vscode, adom-mouser, adom-digikey, adom-jlcpcb, adom-parts-search, adom-gchat | per-user state: Carbon API key, wiki token |
| `adom` user 1001 + sudoers + systemd linger (systemd-nspawn boots systemd as PID1) | |

**Public-build invariants** (smoke-tested, see `image/public-scrub.sh`):
no stale-detector update hook, no GitHub-auth dependency anywhere, and
**no model pins** — Claude Code picks the default model itself.

## Build & release

In an Adom cloud container (no docker — chroot-based; arm64 host or cross-build):

```bash
GOLDEN_VERSION=vN ./scripts/build-rootfs.sh   # → adom-golden-vN-arm64.tar.gz
```

See `skills/golden-image-bake/SKILL.md` for the full monthly procedure.
`image/Dockerfile` is the canonical recipe; `scripts/build-rootfs.sh` is its
docker-less translation. **Keep them in lockstep.**

## Consuming from HD

Pin in `hd-app/src/runtime/macos.rs`:

```rust
pub const TARBALL_URL: &str =
    "https://github.com/adom-inc/hd-lima-image/releases/download/<ver>/adom-golden-<ver>-arm64.tar.gz";
pub const TARBALL_SHA256: &str = "<from the .sha256 asset>";
pub const TARBALL_VERSION: &str = "<ver>-arm64";
```
