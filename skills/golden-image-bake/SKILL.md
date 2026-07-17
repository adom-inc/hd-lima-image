---
name: golden-image-bake
description: Rebuild + release the Hydrogen Desktop golden Lima/nspawn rootfs image (adom-inc/hd-lima-image). Use when the user says "bake the golden image", "rebuild the lima image", "new golden image", "monthly image bake", "cut a new hd-lima-image version", or when CLI/extension/skill drift makes the shipped image stale (target cadence: monthly). EMPLOYEE-ONLY — needs an Adom cloud container with the private hydrogen-desktop checkout; never publish this skill to the public image.
---

# Golden image bake — adom-inc/hd-lima-image

Rebuilds the flat arm64 Rosetta-hybrid rootfs that Hydrogen Desktop `machinectl import-tar`s, with
everything pre-baked (apt baseline, code-server, claude CLI,
Claude Code + adom-vscode extensions, VS Code settings, HD skills, the adom-wiki CLI +
wiki-managed adom skills, Adom CLIs, adom-desktop CLI), then publishes it as a GitHub Release asset.

Repo: `/home/adom/project/hd-lima-image` (github.com/adom-inc/hd-lima-image, public).
Canonical recipe: `image/Dockerfile`; the chroot builder
`scripts/build-rootfs.sh` is its docker-less translation (this container
has no docker) — **keep them in lockstep** when editing either.

## ✅ DONE (v8) — in-machine workspace-updater daemon baked

(Shipped in v8: systemd + systemd-sysv installed so PID 1 is systemd and the
timer fires; daemon at /usr/local/bin/adom-workspace-updater 0.1.2 + enabled
timer; Codex NOT baked — daemon installs it on first boot. The section below is
the reference for how it's wired.)

## (reference) workspace-updater daemon bake

**Gate: ONLY after `feature/hd-auto-update` is merged into hydrogen-desktop
`main`.** Check first: `git ls-tree -r --name-only origin/main -- \
src-tauri/crates/hd-app/resources/workspace-updater/` — if it returns the
files, the gate is open; if empty, SKIP this section (not merged yet).

HD now ships an in-machine auto-updater. HD bootstraps it into the machine on
every launch (`ensure_workspace_updater`), so existing AND new users get it
without an image change — baking it just means a fresh image has the daemon
present before HD's first launch. **Part C invariant (HOLD IT):** the golden
image is FIRST-INSTALL ONLY — never add anything that re-images or migrates
an existing user's machine. All ongoing updates flow through the daemon in
place; the image only benefits brand-new installs.

**KEEP everything currently baked** (code-server, claude-code extension,
adom-vscode, adom-wiki + adom skills, CLIs — all of it stays). The daemon does NOT replace
the bake. Its **first** update installs the **Codex VS Code extension**
(which we do NOT bake) and thereafter converges the container to the live
manifest (SHA-verified, never-downgrade, surgical):
`https://wiki.adom.inc/api/v1/pages/hd-workspace-tooling/files/manifest.json`

Source (hydrogen-desktop main, post-merge):
`src-tauri/crates/hd-app/resources/workspace-updater/`
  - `adom-workspace-updater.sh`      → `/usr/local/bin/adom-workspace-updater` (chmod +x)
  - `adom-workspace-updater.service` → `/etc/systemd/system/`
  - `adom-workspace-updater.timer`   → `/etc/systemd/system/` (then `systemctl enable`)
  - `README.md` — reference only, do NOT ship into the image

Implementation (apply when the gate opens), in lockstep across all three:
1. **CI** `.github/workflows/build.yml` — extend the HD sparse-checkout to
   also stage the updater dir alongside `skills/public-facing`, copy it to
   `image/workspace-updater/`.
2. **chroot** `scripts/build-rootfs.sh` — stage from the local checkout:
   `sudo cp -r ~/project/hydrogen-desktop/src-tauri/crates/hd-app/resources/workspace-updater "${ROOT}/tmp/"`
3. **`image/bake-hd-setup.sh`** — new step (runs as root):
   ```bash
   install -m 0755 /tmp/workspace-updater/adom-workspace-updater.sh /usr/local/bin/adom-workspace-updater
   install -m 0644 /tmp/workspace-updater/adom-workspace-updater.service /etc/systemd/system/
   install -m 0644 /tmp/workspace-updater/adom-workspace-updater.timer   /etc/systemd/system/
   systemctl enable adom-workspace-updater.timer    # writes the multi-user.target.wants symlink; works offline in chroot/docker
   rm -rf /tmp/workspace-updater
   ```
   (`systemctl enable` on a .timer works without a running systemd — it just
   creates the wants-symlink. If the chroot lacks `systemctl`, fall back to
   `ln -s ../adom-workspace-updater.timer /etc/systemd/system/timers.target.wants/`.)
4. **Smoke** (build-rootfs.sh + CI): assert
   `test -x /usr/local/bin/adom-workspace-updater`,
   `test -f /etc/systemd/system/adom-workspace-updater.timer`, and the enable
   symlink exists. Do NOT assert Codex is present — the daemon installs it at
   runtime, not at bake.

## Preconditions

- `~/project/hydrogen-desktop` exists (HD skills source; pull main for releases)
- ~8 GB free under `/tmp` (`df -h /tmp`)
- No other bake running (`pgrep -f build-rootfs.sh` — shared `/tmp/hd-golden-build` workdir)

## Procedure

**Preferred path — CI (real docker, full smoke incl. native claude verify):**

```bash
cd /home/adom/project/hd-lima-image && git pull --ff-only
gh release list --repo adom-inc/hd-lima-image     # pick next vN
gh workflow run build-golden-image -f version=vN
gh run watch $(gh run list --workflow build-golden-image --limit 1 --json databaseId -q '.[0].databaseId') --exit-status
# CI does build + smoke + release + ghcr push. Then SKIP to step 5 (verify).
# Needs the HD_REPO_TOKEN repo secret (read access to hydrogen-desktop).
```

**Fallback path — local chroot build** (CI down, or iterating on the recipe):

```bash
cd /home/adom/project/hd-lima-image
git pull --ff-only

# 1. Next version: current releases, then increment
gh release list --repo adom-inc/hd-lima-image

# 2. Build (~20 min). ALWAYS in background with a log; gate on SMOKE-OK.
GOLDEN_VERSION=vN ./scripts/build-rootfs.sh > /tmp/hd-golden-build.log 2>&1 &
```

Monitor `/tmp/hd-golden-build.log` for `[build-rootfs ...]` / `[bake-hd-setup ...]`
phase lines. Known-benign noise: `E: Can not write log (Is /dev/pts mounted?)`
(apt in a mount-less chroot). Hard failures print `MISSING ...` / `LEAK ...`
from the smoke test — the build exits non-zero; do NOT release.

```bash
# 3. Verify the build said SMOKE-OK and produced artifacts
grep SMOKE-OK /tmp/hd-golden-build.log
ls -lh /tmp/hd-golden-build/adom-golden-vN-arm64.tar.gz*

# 4. Release (fix the sha256 file to a bare filename first)
cd /tmp/hd-golden-build
sed -i 's|/tmp/hd-golden-build/||' adom-golden-vN-arm64.tar.gz.sha256
gh release create vN adom-golden-vN-arm64.tar.gz adom-golden-vN-arm64.tar.gz.sha256 \
  --repo adom-inc/hd-lima-image --title "Golden Lima/nspawn rootfs (arm64) vN" \
  --notes "<what changed since the last bake>"

# 5. Verify the public download + hash (NEVER skip — release ≠ verified)
curl -fsSL -o /tmp/verify.tar.gz \
  "https://github.com/adom-inc/hd-lima-image/releases/download/vN/adom-golden-vN-arm64.tar.gz"
sha256sum /tmp/verify.tar.gz   # must equal the .sha256 asset
rm -f /tmp/verify.tar.gz
```

## 6. ALWAYS show John the latest in pup (John's standing preference)

After every successful release, show John the NEW version in pup — don't wait
to be asked.

⛔ **NEVER do this with proot/code-server in the cloud container** (see
`cloud-container-safety`: a nested code-server here has bricked the container).
Show it from a **disposable Lima machine on the Mac** instead, via the
`golden-image-test` skill: import the released tarball as a throwaway nspawn
machine (never touch `Adom-Workspace`), start code-server inside it, pup to the
forwarded port, then terminate + remove the throwaway machine after. Confirm it's the right build with
`cat /etc/adom-golden-version` → vN (a stale pup window on an old rootfs shows
the old marker — how John caught a v8 window after v9). This is the SAME run
that validates systemd/timer/daemon, so it doubles as the visual.

If the Mac/Lima is unreachable, say so and defer the visual — do NOT fall
back to proot in the container.

## Hand-off to HD

HD consumes the image via three consts in
`hydrogen-desktop/src-tauri/crates/hd-app/src/runtime/macos.rs`:
`TARBALL_URL`, `TARBALL_SHA256`, `TARBALL_VERSION` (e.g. `vN-arm64`).
After releasing, give the HD thread the new URL + sha256 + version so it
bumps the pins (existing installs migrate via `migrate_to_new_tarball`).

## Invariants (smoke-tested; never regress)

- **Public build**: nothing in the image requires GitHub auth. No
  stale-detector hook (`check-updates.sh`) in
  `~/.claude/settings.json` — `image/public-scrub.sh` enforces this.
- **No model pins**: neither `~/.claude/settings.json` (`model`) nor
  code-server `settings.json` (`claudeCode.selectedModel`) names a model —
  Claude Code picks the default for the user.
- install.mjs success = its `Installation complete` marker, NOT exit code.
- systemd-nspawn boots systemd as PID1; `adom` user + sudoers + linger (no wsl.conf).
