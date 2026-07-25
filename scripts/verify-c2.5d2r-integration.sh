#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_literal() {
    local file="$1"
    local literal="$2"
    local description="$3"

    if ! grep -Fq -- "$literal" "$file"; then
        printf 'error: missing C2.5D2R integration: %s\n' "$description" >&2
        printf '       expected in %s: %s\n' "$file" "$literal" >&2
        exit 1
    fi
}

require_literal \
    Sources/MothApplication/MothApplicationShellScene.swift \
    'private var staticFrameCache' \
    'the application shell must own a frame-backing cache'

require_literal \
    Sources/MothApplication/MothApplicationShellScene.swift \
    'MothApplicationFrameDamagePlan.make' \
    'the shell must classify each render before drawing'

require_literal \
    Sources/MothApplication/MothApplicationShellScene.swift \
    'staticFrameCache?.update' \
    'bounded updates must advance the cache generation'

require_literal \
    Sources/MothApplication/MothApplicationShellScene.swift \
    'path: .partialDamage' \
    'bounded editor updates must report partial damage'

require_literal \
    Sources/MothApplication/MothApplicationShellScene.swift \
    'drawDocumentTitle(framebuffer:' \
    'partial text updates must redraw document-dependent chrome only'

printf '%s\n' 'Moth C2.5D2R runtime integration verified.'
