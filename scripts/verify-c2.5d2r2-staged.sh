#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
    "Sources/MothApplication/MothApplicationShellScene.swift"
    "Dependencies/Luna-UI"
)

for file in "${required[@]}"; do
    git diff --cached --name-only | grep -Fxq "$file" || {
        printf 'error: required staged path is missing: %s\n' "$file" >&2
        exit 1
    }
done

staged_shell="$(
    git show :Sources/MothApplication/MothApplicationShellScene.swift
)"

grep -Fq 'path: .partialDamage' <<<"$staged_shell" || {
    printf '%s\n' \
        'error: staged Moth shell lacks .partialDamage' >&2
    exit 1
}

grep -Fq 'MothApplicationFrameDamagePlan.make' <<<"$staged_shell" || {
    printf '%s\n' \
        'error: staged Moth shell lacks runtime damage planning' >&2
    exit 1
}

grep -Fq 'staticFrameCache?.update' <<<"$staged_shell" || {
    printf '%s\n' \
        'error: staged Moth shell lacks cache update' >&2
    exit 1
}

git diff --cached --check

printf '%s\n' \
    'Moth C2.5D2R2 shell and Luna gitlink are staged and verified.'
