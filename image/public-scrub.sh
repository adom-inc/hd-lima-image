#!/usr/bin/env bash
# public-scrub.sh — run as root inside the rootfs after the Hydrogen setup bake.
#
# This image ships to the public. Strip everything that phones home to
# private infra or assumes GitHub auth:
#   - any stale-detector update hook (UserPromptSubmit → check-updates.sh):
#     a periodic `git fetch` against a private repo — wrong for non-employee
#     machines. Updates ship as new image versions instead.
#   - the "model" pin (opus[1m]) in ~/.claude/settings.json: Claude Code must pick
#     its own default model on public installs. WRITTEN BY adom/hook's install.sh,
#     NOT by adom/core (which is a pure dependency manifest with no scripts; it just
#     pulls in the hook). This comment said adom/core until 2026-07-28 and cost a
#     round trip chasing the wrong package — the write is `d["model"] = "opus[1m]"`
#     in hook's install.sh, guarded only-if-absent and skippable with
#     ADOM_HOOK_NO_MODEL_DEFAULT=1.
#
#     NOTE the del(.model) below is bake-time only, so it does NOT hold: adom/hook
#     re-installs on every `adom-wiki pkg update` (the auto-updater kept below) and
#     the only-if-absent write refills the key days after the image ships. Hydrogen sets
#     ADOM_HOOK_NO_MODEL_DEFAULT=1 machine-wide at launch, which is what actually
#     keeps it unpinned; deleting alone just feeds the refill.
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

# Make the del(.model) above actually STICK. Without this the next `adom-wiki pkg
# update` re-runs adom/hook's install and its only-if-absent write refills the key —
# so the image ships unpinned and drifts back to pinned within a day of normal use.
# Three files because the hook can fire from three shell paths: PAM/nspawn services
# (/etc/environment), login shells (profile.d), and code-server's interactive
# non-login terminal (.bashrc). Idempotent; Hydrogen asserts the same thing at launch, so
# an image baked before this still self-heals.
grep -q '^ADOM_HOOK_NO_MODEL_DEFAULT=' /etc/environment 2>/dev/null \
    || echo 'ADOM_HOOK_NO_MODEL_DEFAULT=1' >> /etc/environment
printf '%s\n' \
    '# Public image: Claude Code picks its own default model (adom/hook opt-out).' \
    'export ADOM_HOOK_NO_MODEL_DEFAULT=1' > /etc/profile.d/hydrogen-no-model-pin.sh
chmod 0644 /etc/profile.d/hydrogen-no-model-pin.sh
if [[ -f /home/adom/.bashrc ]] && ! grep -q ADOM_HOOK_NO_MODEL_DEFAULT /home/adom/.bashrc; then
    echo 'export ADOM_HOOK_NO_MODEL_DEFAULT=1  # Claude Code picks its own model' >> /home/adom/.bashrc
fi

rm -f /home/adom/.adom/last-update-check \
      /home/adom/.adom/last-wiki-check \
      /home/adom/.adom/last-wiki-fetch-fail
