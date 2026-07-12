#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
luna_path="$repo_root/Dependencies/Luna-UI"
cd "$repo_root"

# Initialize only Moth's intended Luna dependency at the currently recorded
# gitlink. Never recurse into repositories or recovery artifacts inside Luna.
git submodule sync -- Dependencies/Luna-UI
git submodule update --init --checkout Dependencies/Luna-UI

# Do not destroy local work inside the dependency checkout.
if ! git -C "$luna_path" diff --quiet || ! git -C "$luna_path" diff --cached --quiet; then
    echo "error: Dependencies/Luna-UI has tracked local changes." >&2
    echo "       Commit, stash, or discard those changes before updating the dependency." >&2
    exit 1
fi

# Advance Luna to the cloud main branch without leaving the submodule detached.
git -C "$luna_path" fetch --prune origin main
git -C "$luna_path" switch --force-create main origin/main
git -C "$luna_path" branch --set-upstream-to=origin/main main >/dev/null

# Moth M2.2A uses Luna's public theme infrastructure plus the Phase 5F.2A
# pane-content and soft-wrap surfaces. Fail early on an older Luna checkout.
required_product='.library(name: "LunaTheme", targets: ["LunaTheme"])'
if ! grep -Fq "$required_product" "$luna_path/Package.swift"; then
    echo "error: the checked-out Luna-UI main branch does not export LunaTheme." >&2
    echo "       Moth M2.2A requires Luna UI Phase 5F.2A or newer." >&2
    exit 1
fi

if ! grep -Fq 'public struct LunaPaneContentFrame' "$luna_path/Sources/LunaUI/LunaPaneContainer.swift" ||    ! grep -Fq 'case soft' "$luna_path/Sources/LunaUI/LunaStaticTextView.swift"; then
    echo "error: the checked-out Luna-UI revision lacks Phase 5F.2A pane-bound soft-wrap APIs." >&2
    echo "       Commit and push Luna Phase 5F.2A before updating Moth." >&2
    exit 1
fi

printf 'Luna branch: '
git -C "$luna_path" branch --show-current
printf 'Luna commit: '
git -C "$luna_path" log -1 --oneline
printf 'Moth gitlink: '
git submodule status Dependencies/Luna-UI

cat <<'MSG'
Luna-UI is ready for Moth M2.2A.
The modified Dependencies/Luna-UI gitlink is expected and must be committed with Moth after validation.
Do not run another plain `git submodule update` before committing Moth.
MSG
