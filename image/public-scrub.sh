#!/usr/bin/env bash
# public-scrub.sh — run as root inside the rootfs after the HD setup bake.
#
# This image ships to the public. Strip everything that phones home to
# private infra or assumes GitHub auth:
#   - any stale-detector update hook (UserPromptSubmit → check-updates.sh):
#     a periodic `git fetch` against a private repo — wrong for non-employee
#     machines. Updates ship as new image versions instead.
#   - adom/core postinstall's cloud-container defaults in ~/.claude/settings.json:
#     the adom-core-update.sh UserPromptSubmit hook (+ its ~/.adom/hooks script) and
#     the "model" pin (opus[1m]) — Claude Code must pick its own default model on
#     public installs, and workspace updates come from the workspace-updater daemon.
#     (These started landing in the bake once adom-wiki began actually RUNNING
#     package install scripts, v12 2026-07-17.)
#   - bake-time update stamps under ~/.adom
#
# Keep idempotent; both scripts/build-rootfs.sh (chroot) and
# image/Dockerfile (CI) run this same file.

set -euo pipefail

S=/home/adom/.claude/settings.json
if [[ -f "$S" ]]; then
    jq 'del(.model)
        | (.hooks.UserPromptSubmit // []) |= map(
            select(((.hooks // []) | any(.command // ""
                | (contains("check-updates.sh") or contains("adom-core-update")))) | not))
        | if ((.hooks.UserPromptSubmit // []) | length) == 0 then del(.hooks.UserPromptSubmit) else . end
        | if ((.hooks // {}) | length) == 0 then del(.hooks) else . end' \
        "$S" > "$S.tmp"
    mv "$S.tmp" "$S"
    chown 1001:1001 "$S"
fi
rm -f /home/adom/.adom/hooks/adom-core-update.sh
rmdir /home/adom/.adom/hooks 2>/dev/null || true

rm -f /home/adom/.adom/last-update-check \
      /home/adom/.adom/last-wiki-check \
      /home/adom/.adom/last-wiki-fetch-fail
