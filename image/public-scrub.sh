#!/usr/bin/env bash
# public-scrub.sh — run as root inside the rootfs after the HD setup bake.
#
# This image ships to the public. Strip everything that phones home to
# private infra or assumes GitHub auth:
#   - any stale-detector update hook (UserPromptSubmit → check-updates.sh):
#     a periodic `git fetch` against a private repo — wrong for non-employee
#     machines. Updates ship as new image versions instead.
#   - adom/core postinstall's "model" pin (opus[1m]) in ~/.claude/settings.json:
#     Claude Code must pick its own default model on public installs.
#   - bake-time update stamps under ~/.adom
#
# KEEP the adom/hook auto-updater (UserPromptSubmit → ~/.adom/hooks/adom-core-update.sh
# + its cron + Codex wiring). Since the workspace-updater daemon retired (main
# 2026-07-16), registry-native updates via `adom-wiki pkg update` on this hook ARE
# how the workspace stays current — so the golden image MUST ship it wired (fixing the
# 2026-07-22 dead-trigger state: the hook script was scrubbed but its cron/Codex
# entries survived, pointing at a missing file). Only the legacy `check-updates.sh`
# stale-detector (a git-fetch against a private repo) is stripped.
#
# Keep idempotent; both scripts/build-rootfs.sh (chroot) and
# image/Dockerfile (CI) run this same file.

set -euo pipefail

S=/home/adom/.claude/settings.json
if [[ -f "$S" ]]; then
    jq 'del(.model)
        | (.hooks.UserPromptSubmit // []) |= map(
            select(((.hooks // []) | any(.command // ""
                | contains("check-updates.sh"))) | not))
        | if ((.hooks.UserPromptSubmit // []) | length) == 0 then del(.hooks.UserPromptSubmit) else . end
        | if ((.hooks // {}) | length) == 0 then del(.hooks) else . end' \
        "$S" > "$S.tmp"
    mv "$S.tmp" "$S"
    chown 1001:1001 "$S"
fi

rm -f /home/adom/.adom/last-update-check \
      /home/adom/.adom/last-wiki-check \
      /home/adom/.adom/last-wiki-fetch-fail
