#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUNA="$ROOT/Dependencies/Luna-UI"

fail() {
  printf 'M2.2B2 integration verification failed: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: ${1#$ROOT/}"
}

require_text() {
  local file="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$file" || fail "missing '$pattern' in ${file#$ROOT/}"
}

for file in \
  "$ROOT/Sources/MothApplication/MothCommandSystem.swift" \
  "$ROOT/Sources/MothApplication/MothApplicationShellScene.swift" \
  "$ROOT/Sources/MothApplication/MothDocumentSheetWorkspace.swift" \
  "$ROOT/Sources/MothApplication/MothPaneEditorSurface.swift" \
  "$ROOT/Sources/MothEditor/MothFindSession.swift" \
  "$ROOT/Tests/MothApplicationTests/MothM22B2ClipboardFindTests.swift" \
  "$ROOT/docs/M2.2B2_CLIPBOARD_AND_FIND_REPLACE.md" \
  "$LUNA/Sources/LunaHostCore/LunaClipboardService.swift" \
  "$LUNA/Sources/LunaHostSDL/LunaSDLClipboardService.swift" \
  "$LUNA/Sources/LunaUI/LunaEditableFieldState.swift" \
  "$LUNA/docs/M2.2B2_CLIPBOARD_AND_EDITABLE_FIELDS.md"
do
  require_file "$file"
done

COMMANDS="$ROOT/Sources/MothApplication/MothCommandSystem.swift"
SHELL="$ROOT/Sources/MothApplication/MothApplicationShellScene.swift"
SHEETS="$ROOT/Sources/MothApplication/MothDocumentSheetWorkspace.swift"
FIND="$ROOT/Sources/MothEditor/MothFindSession.swift"
SDL="$LUNA/Sources/LunaHostSDL/LunaSDLApplication.swift"

require_text "$COMMANDS" 'moth.edit.copy'
require_text "$COMMANDS" 'moth.edit.cut'
require_text "$COMMANDS" 'moth.edit.paste'
require_text "$COMMANDS" 'moth.find.replaceAll'
require_text "$SHELL" 'Clipboard write must succeed before any destructive mutation.'
require_text "$SHELL" 'findHighlights(for:'
require_text "$SHELL" 'refreshFindPanelAfterDocumentMutation()'
require_text "$SHEETS" 'public var findPanelState: LunaFindPanelState'
require_text "$FIND" 'Invalid regular expression:'
require_text "$FIND" 'intent: .replaceAll'
require_text "$SDL" 'applicationID: String?'
require_text "$SDL" 'SDL_VIDEO_WAYLAND_WMCLASS'
require_text "$ROOT/Sources/MothTextLinux/main.swift" 'applicationID: "io.github.adamjvr.MothText"'
require_text "$ROOT/Sources/MothTextLinux/main.swift" 'windowClass: "MothTextLinux"'

if grep -Fq 'Visible Find/Replace is planned for M2.2B2' "$SHELL"; then
  fail "stale disabled Find implementation remains"
fi

if grep -R --line-number -E 'git (switch -c|checkout -b|branch m2\.2b2)' \
  "$ROOT/scripts" "$ROOT/docs/M2.2B2_CLIPBOARD_AND_FIND_REPLACE.md" >/dev/null 2>&1; then
  fail "phase-specific branch creation was introduced"
fi

printf 'M2.2B2 integration verification passed.\n'
