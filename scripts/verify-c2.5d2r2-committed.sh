#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

shell="Sources/MothApplication/MothApplicationShellScene.swift"
old_shell_blob="15bd2a89c991ad600b17abdcf48c2d8e9b6c94d2"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

committed_shell_blob="$(git rev-parse "HEAD:$shell")"
[[ "$committed_shell_blob" != "$old_shell_blob" ]] || \
    fail "$shell was not committed; HEAD still contains the old blob"

changed_files="$(git diff-tree --no-commit-id --name-only -r HEAD)"
grep -Fxq "$shell" <<<"$changed_files" || \
    fail "latest commit does not include $shell"
grep -Fxq "Dependencies/Luna-UI" <<<"$changed_files" || \
    fail "latest commit does not include the Luna gitlink"

git show "HEAD:$shell" \
    | grep -Fq 'private var staticFrameCache' || \
    fail "committed shell lacks the static frame cache"

git show "HEAD:$shell" \
    | grep -Fq 'MothApplicationFrameDamagePlan.make' || \
    fail "committed shell lacks runtime damage planning"

git show "HEAD:$shell" \
    | grep -Fq 'path: .partialDamage' || \
    fail "committed shell lacks partial-damage reporting"

git show "HEAD:$shell" \
    | grep -Fq 'staticFrameCache?.update' || \
    fail "committed shell lacks post-redraw cache updates"

recorded_luna_sha="$(git rev-parse HEAD:Dependencies/Luna-UI)"
checked_out_luna_sha="$(git -C Dependencies/Luna-UI rev-parse HEAD)"

[[ "$recorded_luna_sha" == "$checked_out_luna_sha" ]] || \
    fail "Moth HEAD gitlink and checked-out Luna SHA do not match"

printf '%s\n' \
    'Moth C2.5D2R2 committed runtime integration verified.'
printf 'HEAD: %s\n' "$(git rev-parse HEAD)"
printf 'shell blob: %s\n' "$committed_shell_blob"
printf 'Luna gitlink: %s\n' "$recorded_luna_sha"
