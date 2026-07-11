#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ ! -f Dependencies/Luna-UI/Package.swift ]]; then
    echo "Luna-UI dependency is not initialized." >&2
    exit 1
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    status="$(git submodule status -- Dependencies/Luna-UI 2>/dev/null || true)"
    if [[ -n "$status" ]]; then
        first="${status:0:1}"
        case "$first" in
            -) echo "Luna-UI submodule is not initialized." >&2; exit 1 ;;
            +) echo "Luna-UI is checked out at a different commit than Moth pins." >&2; exit 1 ;;
            U) echo "Luna-UI submodule has merge conflicts." >&2; exit 1 ;;
        esac
    fi
fi

echo "Luna-UI dependency is present."
