#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git submodule update --init --recursive
fi

if [[ ! -f Dependencies/Luna-UI/Package.swift ]]; then
    printf 'error: Dependencies/Luna-UI is missing.\n' >&2
    printf 'Clone with --recurse-submodules or run git submodule update --init --recursive.\n' >&2
    exit 1
fi

swift build
swift test
