#!/usr/bin/env bash
# public-scrub.sh — run as root inside the rootfs after the HD setup bake.
#
# This image ships to the public. Strip everything that phones home to
# private infra or assumes GitHub auth:
#   - any stale-detector update hook (UserPromptSubmit → check-updates.sh):
#     a periodic `git fetch` against a private repo — wrong for non-employee
#     machines. Updates ship as new image versions instead.
#   - bake-time update stamps under ~/.adom
#
# Keep idempotent; both scripts/build-rootfs.sh (chroot) and
# image/Dockerfile (CI) run this same file.

set -euo pipefail

S=/home/adom/.claude/settings.json
if [[ -f "$S" ]]; then
    jq '(.hooks.UserPromptSubmit // []) |= map(
            select(((.hooks // []) | any(.command // "" | contains("check-updates.sh"))) | not))
        | if ((.hooks.UserPromptSubmit // []) | length) == 0 then del(.hooks.UserPromptSubmit) else . end' \
        "$S" > "$S.tmp"
    mv "$S.tmp" "$S"
    chown 1001:1001 "$S"
fi

rm -f /home/adom/.adom/last-update-check \
      /home/adom/.adom/last-wiki-check \
      /home/adom/.adom/last-wiki-fetch-fail
