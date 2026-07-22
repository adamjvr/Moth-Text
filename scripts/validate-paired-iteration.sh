#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff HEAD --check
fi

./scripts/verify-submodules.sh

expected_luna_commit="$(git ls-files --stage Dependencies/Luna-UI | awk '{print $2}')"
actual_luna_commit="$(git -C Dependencies/Luna-UI rev-parse HEAD)"

if [[ -z "$expected_luna_commit" || "$expected_luna_commit" != "$actual_luna_commit" ]]; then
    printf 'error: Luna-UI checkout does not match Moth\x27s recorded gitlink.\n' >&2
    printf 'expected: %s\n' "${expected_luna_commit:-<missing>}" >&2
    printf 'actual:   %s\n' "$actual_luna_commit" >&2
    exit 1
fi

if [[ -n "$(git -C Dependencies/Luna-UI status --porcelain)" ]]; then
    printf 'error: Luna-UI submodule contains uncommitted changes.\n' >&2
    exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
    printf 'error: pkg-config is required to validate Moth Text.\n' >&2
    exit 1
fi

for package in sdl2 harfbuzz freetype2; do
    if ! pkg-config --exists "$package"; then
        printf 'error: required pkg-config package is unavailable: %s\n' "$package" >&2
        exit 1
    fi
done

printf '%s\n' '==> Swift toolchain'
swift --version

printf '%s\n' '==> Pinned Luna UI revision'
printf '%s\n' "$actual_luna_commit"

printf '%s\n' '==> Resolving Moth Text package'
swift package resolve

printf '%s\n' '==> Building Moth Text and all test products'
swift build --build-tests

printf '%s\n' '==> Building application and plugin-host products explicitly'
swift build --product MothTextLinux
swift build --product MothPluginHost

printf '%s\n' '==> Running complete Moth Text test suite'
swift test

printf '%s\n' '==> Running headless application/render bootstrap smoke test'
swift run MothTextLinux --headless-smoke

printf '%s\n' '==> Running plugin-host IPC smoke test'
./scripts/smoke-test-plugin-host.sh

printf '\nAutomated Moth validation passed against Luna-UI commit:\n%s\n' "$actual_luna_commit"
printf '\nBefore committing, manually launch and inspect Moth Text:\n\n'
printf '    swift run MothTextLinux\n\n'
printf 'Do not commit Moth Text until the manual application smoke test passes.\n'
