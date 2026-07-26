#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
expected_branch="a1.1-measured-audit"
expected_head="f4941d6b7c6b2bdac5bb0b826076eaee315e75a6"
expected_shell_blob="15bd2a89c991ad600b17abdcf48c2d8e9b6c94d2"
patch_file="patches/C2.5D2R2_MOTH_VERIFIED_RUNTIME_INTEGRATION.patch"
fail(){ printf 'error: %s\n' "$*" >&2; exit 1; }
branch="$(git branch --show-current)"
[[ "$branch" == "$expected_branch" ]] || fail "expected branch $expected_branch, found ${branch:-detached HEAD}"
head_sha="$(git rev-parse HEAD)"
[[ "$head_sha" == "$expected_head" ]] || fail "expected C2.5D2R commit $expected_head, found $head_sha"
unexpected="$(git diff --name-only | grep -v '^Dependencies/Luna-UI$' || true)"
[[ -z "$unexpected" ]] || { printf '%s\n' 'error: unrelated tracked changes already exist:' >&2; printf '%s\n' "$unexpected" >&2; exit 1; }
git diff --cached --quiet || fail "staged changes already exist; commit or unstage them first"
shell_blob="$(git rev-parse HEAD:Sources/MothApplication/MothApplicationShellScene.swift)"
[[ "$shell_blob" == "$expected_shell_blob" ]] || fail "unexpected MothApplicationShellScene.swift baseline blob: $shell_blob"
git diff --quiet -- Dependencies/Luna-UI && fail "advance Dependencies/Luna-UI to the committed Luna C2.5D2R2 SHA first"
git -C Dependencies/Luna-UI status --short | grep -q . && fail "the Luna submodule worktree is dirty"
python3 scripts/apply-exact-unified-diff.py --repo-root "$repo_root" --patch "$patch_file"
./scripts/verify-c2.5d2r2-working-tree.sh
printf '\n%s\n' 'Moth C2.5D2R2 source patch applied and verified in the working tree.'
printf '%s\n' 'Run focused tests, paired validation, and native acceptance before staging.'
