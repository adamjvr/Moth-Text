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

require_literal() {
    local literal="$1"
    local description="$2"
    grep -Fq -- "$literal" "$shell" || \
        fail "$description is missing from $shell"
}

git diff --quiet -- "$shell" && \
    fail "$shell has no working-tree source change"

new_shell_blob="$(git hash-object "$shell")"
[[ "$new_shell_blob" != "$old_shell_blob" ]] || \
    fail "$shell still hashes to the pre-repair blob"

require_literal \
    'private var staticFrameCache: MothApplicationStaticFrameCache?' \
    'Moth-owned static frame cache'

require_literal \
    'MothApplicationFrameDamagePlan.make' \
    'runtime damage planning'

require_literal \
    'cache.restore(' \
    'bounded backing-frame restoration'

require_literal \
    'drawPartialFrame(' \
    'partial redraw path'

require_literal \
    'staticFrameCache?.update' \
    'post-redraw cache update'

require_literal \
    'path: .partialDamage' \
    'partial-damage frame reporting'

require_literal \
    'damagedRegionCount: damagePlan.regions.count' \
    'damaged-region diagnostics'

require_literal \
    'damagedPixelCount: restoredPixels' \
    'damaged-pixel diagnostics'

require_literal \
    'staticFrameCache = nil' \
    'cache invalidation'

git diff --check -- "$shell"

printf '%s\n' \
    'Moth C2.5D2R2 working-tree runtime integration verified.'
