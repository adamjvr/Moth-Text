#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ ! -f Dependencies/Luna-UI/Package.swift ]]; then
    printf 'Luna-UI dependency is not initialized.\n' >&2
    exit 1
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C Dependencies/Luna-UI status --porcelain)" ]]; then
        printf 'Luna-UI submodule contains uncommitted changes.\n' >&2
        exit 1
    fi

    expected="$(git ls-files --stage Dependencies/Luna-UI | awk '{print $2}')"
    actual="$(git -C Dependencies/Luna-UI rev-parse HEAD)"

    if [[ -z "$expected" ]]; then
        printf 'Moth does not have a staged or recorded Luna-UI gitlink.\n' >&2
        exit 1
    fi
    if [[ "$expected" != "$actual" ]]; then
        printf 'Luna-UI checkout does not match Moth\x27s index gitlink.\n' >&2
        printf 'expected: %s\n' "$expected" >&2
        printf 'actual:   %s\n' "$actual" >&2
        printf 'After an intentional Luna update, run: git add Dependencies/Luna-UI\n' >&2
        exit 1
    fi
fi

printf 'Luna-UI dependency is present at the recorded index revision.\n'
