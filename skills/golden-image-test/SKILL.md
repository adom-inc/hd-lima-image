---
name: golden-image-test
description: Test/preview the HD golden arm64 Rosetta-hybrid rootfs by importing it into a DISPOSABLE systemd-nspawn machine inside a throwaway Lima VM on the user's Mac (real systemd PID 1 → exercises the timer + workspace-updater daemon AND gives a real code-server to pup). Use when the user says "test the golden image", "run the golden image", "serve the rootfs", "let me see the golden code-server", "verify the image config", or reports something wrong/missing in a golden image build. Every confirmed gap gets added to image/bake-hd-setup.sh AND a smoke assertion in scripts/build-rootfs.sh — that is the rule.
---

# Golden image test — disposable Lima machine (macOS)

Validate a built/released golden image the way HD actually runs it: as a
**systemd-nspawn machine** booted inside a **Lima vz VM** on the Mac, with
**systemd as PID 1** — so the timer + workspace-updater daemon actually fire,
and you get a real code-server to pup. The user's real `Adom-Workspace` is
never touched; the throwaway machine is terminated + removed afterward.

> ⛔ NEVER preview with proot/code-server in an Adom cloud container (see
> `cloud-container-safety`). The Lima-machine test below is the macOS path.

## The test — import into a DISPOSABLE nspawn machine in a throwaway Lima VM

This mirrors `runtime/macos.rs` exactly (limactl shell → machinectl import-tar
→ systemd-nspawn boot → nsenter), but against a `golden-test-vN` machine in a
throwaway `lima-golden-test` VM, so the user's `hd-builder` + `Adom-Workspace`
are untouched.

```bash
# 0. Throwaway Lima VM (vz + Rosetta), separate from HD's hd-builder:
limactl start --name=lima-golden-test --vm-type=vz --rosetta --tty=false
L() { limactl shell lima-golden-test -- sudo "$@"; }
L bash -lc 'command -v machinectl || { apt-get update -qq && apt-get install -y -qq systemd-container; }'

# 1. Pull the released arm64 tarball INTO the VM, import as golden-test-vN:
limactl shell lima-golden-test -- bash -lc \
  'curl -fL "https://github.com/adom-inc/hd-lima-image/releases/download/vN/adom-golden-vN-arm64.tar.gz" -o /tmp/g.tar.gz'
L machinectl import-tar /tmp/g.tar.gz golden-test-vN

# 2. Boot it (systemd PID1) and confirm:
L systemd-run --unit golden-test --collect -- \
   systemd-nspawn --boot --quiet --directory /var/lib/machines/golden-test-vN --resolv-conf=copy-host
L machinectl shell golden-test-vN /bin/cat /proc/1/comm          # → systemd
L machinectl shell golden-test-vN /bin/cat /etc/adom-golden-version  # → vN-arm64 (guards stale builds)

# 3. Exercise the daemon + Rosetta + extensions (run as adom via nsenter):
LEADER=$(L machinectl show golden-test-vN -p Leader --value)
A() { L nsenter -t "$LEADER" -a -S 1001 -G 1001 -- /usr/bin/env HOME=/home/adom USER=adom bash -lc "$1"; }
A 'systemctl start adom-workspace-updater.service; cat ~/.adom/workspace-updater-status.json'  # updated/pending sane
A 'adom-desktop --version'                          # x86-64 binary running under Rosetta
A '/usr/lib/code-server/bin/code-server --list-extensions | grep -E "anthropic.claude-code|^adom"'

# 4. Browser/pup view: start code-server in the machine, forward the port to the host.
A 'setsid /usr/lib/code-server/bin/code-server --bind-addr 0.0.0.0:7399 >/tmp/cs.log 2>&1 </dev/null & disown; echo ok'
#    Reach it from the Mac on the Lima-forwarded port, then pup to it.

# 5. CLEANUP (always):
L machinectl terminate golden-test-vN || true
L machinectl remove golden-test-vN || true
limactl delete -f lima-golden-test
```

This validates everything that matters — systemd PID 1, the timer + updater
daemon, Rosetta execution of x86-64 Adom binaries, code-server + extensions —
and gives a real code-server to pup, without touching the user's workspace.

## Notes

- `cat /etc/adom-golden-version` → `vN-arm64` confirms you're testing the build
  you think you are (a stale pup window on an old rootfs shows the old marker).
- `host.docker.internal` / `adom-host` alias is written per machine-start by
  `init-host-internal.sh` (mirrors `runtime/macos.rs init_host_alias`).
- The rule: every confirmed gap → a new step in `image/bake-hd-setup.sh` AND a
  smoke assertion in `scripts/build-rootfs.sh`.
