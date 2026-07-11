#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Initialize only Moth's declared Luna dependency. Deliberately avoid
    # --recursive so accidental repositories inside Luna cannot affect Moth.
    git submodule sync -- Dependencies/Luna-UI
    git submodule update --init Dependencies/Luna-UI
fi

if [[ ! -f Dependencies/Luna-UI/Package.swift ]]; then
    printf 'error: Dependencies/Luna-UI is missing.\n' >&2
    printf 'Run: git submodule update --init Dependencies/Luna-UI\n' >&2
    exit 1
fi

swift build
swift test
