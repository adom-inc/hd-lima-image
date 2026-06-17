#!/usr/bin/env bash
# init-host-internal.sh — write the `adom-host` (and legacy `host.docker.internal`)
# alias into /etc/hosts so Adom code that talks to the macOS host keeps working
# inside the workspace.
#
# macOS/Lima model: the workspace runs as a systemd-nspawn machine sharing the
# network of an HD-owned Lima vz VM. Apple's Virtualization.framework does NOT
# mirror the host loopback (unlike WSL's mirrored mode), so host services are
# reached via the VM's gateway, exposed in the machine as `adom-host`.
#
# Idempotent: removes any prior line we wrote and rewrites against the current
# default-route gateway. Called by MacosVmRuntime (runtime/macos.rs init_host_alias)
# at machine start; also safe to run manually for diagnostics.
# VERIFY against runtime/macos.rs init_host_alias — that Rust path is the system of
# record for the gateway it injects; this baked copy must agree with it.

set -euo pipefail

MARKER="# adom-host-internal"
HOSTS=/etc/hosts

# The host is reached at the VM's default-route gateway (vz user-mode networking).
HOST_IP="$(ip route 2>/dev/null | awk '/^default/ { print $3; exit }' || true)"

if [[ -z "${HOST_IP:-}" ]]; then
    echo "init-host-internal: no default-route gateway, skipping" >&2
    exit 0
fi

# Remove any prior line we wrote, then append the fresh one. `sudo` so this runs
# cleanly under the default `adom` user too — passwordless sudo is granted in the build.
sudo sed -i "/${MARKER}\$/d" "${HOSTS}"
echo "${HOST_IP} adom-host host.docker.internal ${MARKER}" | sudo tee -a "${HOSTS}" >/dev/null

echo "init-host-internal: adom-host -> ${HOST_IP}"
