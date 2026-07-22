#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
luna_path="$repo_root/Dependencies/Luna-UI"
cd "$repo_root"

# Initialize only Moth's intended Luna dependency at the recorded gitlink.
git submodule sync -- Dependencies/Luna-UI
git submodule update --init --checkout Dependencies/Luna-UI

# Never destroy local work inside the dependency checkout.
if ! git -C "$luna_path" diff --quiet || ! git -C "$luna_path" diff --cached --quiet; then
    echo "error: Dependencies/Luna-UI has tracked local changes." >&2
    echo "       Commit, stash, or discard those changes before updating." >&2
    exit 1
fi

# Advance Luna to cloud main without leaving the submodule detached.
git -C "$luna_path" fetch --prune origin main
git -C "$luna_path" switch --force-create main origin/main
git -C "$luna_path" branch --set-upstream-to=origin/main main >/dev/null

required_product='.library(name: "LunaTheme", targets: ["LunaTheme"])'
if ! grep -Fq "$required_product" "$luna_path/Package.swift"; then
    echo "error: Luna-UI main does not export LunaTheme." >&2
    exit 1
fi

unicode_product='.library(name: "LunaTextRender", targets: ["LunaTextRender"])'
unicode_renderer="$luna_path/Sources/LunaTextRender/LunaUnicodeTextRenderer.swift"
if ! grep -Fq "$unicode_product" "$luna_path/Package.swift" || \
   ! grep -Fq 'public final class LunaUnicodeTextRenderer' "$unicode_renderer" || \
   ! grep -Fq 'bestMonospacedFontPath' "$luna_path/Sources/LunaText/LunaFontLocator.swift"; then
    echo "error: Luna-UI lacks the Convergence C2.1 Unicode text-rendering contract." >&2
    exit 1
fi

if ! grep -Fq 'public struct LunaPaneContentFrame' "$luna_path/Sources/LunaUI/LunaPaneContainer.swift" || \
   ! grep -Fq 'case soft' "$luna_path/Sources/LunaUI/LunaStaticTextView.swift"; then
    echo "error: Luna-UI lacks Phase 5F.2A pane-bound soft-wrap APIs." >&2
    exit 1
fi

if ! grep -Fq 'public enum LunaCursorIntent' "$luna_path/Sources/LunaHostCore/LunaCursorIntent.swift" || \
   ! grep -Fq 'public struct LunaPaneContainerInteractionState' "$luna_path/Sources/LunaUI/LunaPaneContainer.swift"; then
    echo "error: Luna-UI lacks Convergence C1A cursor/pane interaction APIs." >&2
    exit 1
fi

if ! grep -Fq 'var wantsPointerCapture: Bool' "$luna_path/Sources/LunaHostSDL/LunaSDLApplication.swift"; then
    echo "error: Luna-UI lacks the SDL pointer-capture scene contract." >&2
    exit 1
fi

selection_api="$luna_path/Sources/LunaUI/LunaTextSelectionInteraction.swift"
if ! grep -Fq 'public struct LunaTextSelectionInteractionState' "$selection_api" || \
   ! grep -Fq 'public enum LunaTextSelectionInteraction' "$selection_api" || \
   ! grep -Fq 'public static func advanceAutoscroll' "$selection_api" || \
   ! grep -Fq 'func wordRange(at location: LunaTextLocation)' "$selection_api" || \
   ! grep -Fq 'func logicalLineRange(at location: LunaTextLocation)' "$selection_api"; then
    echo "error: Luna-UI lacks Convergence C1B text-selection APIs." >&2
    exit 1
fi

printf 'Luna branch: '
git -C "$luna_path" branch --show-current
printf 'Luna commit: '
git -C "$luna_path" log -1 --oneline
printf 'Moth gitlink: '
git submodule status Dependencies/Luna-UI

cat <<'MSG'
Luna-UI is ready for Moth Convergence C2.1.
C2.1 exports the product-neutral LunaTextRender shaped Unicode painter while
preserving Moth ownership of documents, history, workspace policy, and chrome.
The modified Dependencies/Luna-UI gitlink must be committed with Moth after validation.
Do not run another plain `git submodule update` before committing Moth.
MSG
