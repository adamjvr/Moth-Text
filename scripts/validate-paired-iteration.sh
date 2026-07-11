#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

./scripts/verify-submodules.sh

if git -C Dependencies/Luna-UI rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C Dependencies/Luna-UI status --porcelain)" ]]; then
        echo "Luna-UI submodule contains uncommitted changes." >&2
        exit 1
    fi
fi

echo "==> Resolving Moth Text package"
swift package resolve

echo "==> Building all Moth Text targets"
swift build

echo "==> Building application and plugin-host products explicitly"
swift build --product MothTextLinux
swift build --product MothPluginHost

echo "==> Running complete Moth Text test suite"
swift test

echo "==> Running non-interactive Moth application bootstrap smoke test"
swift run MothTextLinux

echo
echo "Automated Moth validation passed against Luna-UI commit:"
git -C Dependencies/Luna-UI rev-parse --short HEAD

echo
echo "Before committing, manually launch and inspect Moth Text:"
echo
echo "    swift run MothTextLinux"
echo
echo "Optional plugin-host IPC integration smoke test:"
echo
echo "    ./scripts/smoke-test-plugin-host.sh"
echo
echo "Do not commit Moth Text until the manual application smoke test passes."
