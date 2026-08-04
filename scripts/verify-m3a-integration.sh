#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  "Sources/MothApplication/MothDocumentSheetWorkspace.swift"
  "Sources/MothApplication/MothCommandSystem.swift"
  "Tests/MothApplicationTests/MothM3ADocumentSheetTests.swift"
  "docs/M3A_DOCUMENT_SHEETS_AND_TABS.md"
  "docs/ARCHITECTURE.md"
  "docs/LUNA_INTEGRATION.md"
  "packaging/linux/io.github.adamjvr.MothText.desktop"
  "packaging/linux/hicolor/256x256/apps/io.github.adamjvr.MothText.png"
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    printf 'error: missing M3A path: %s\n' "$path" >&2
    exit 1
  }
done

grep -q 'public struct MothDocumentSheetID' \
  Sources/MothApplication/MothDocumentSheetWorkspace.swift
grep -q 'public private(set) var documentSheets' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'private mutating func handleDocumentTabsPointer' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'private mutating func handleOpenFilesPointer' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'MothCommandID.closeTab' \
  Sources/MothApplication/MothCommandSystem.swift
grep -q 'MothCommandID.nextTab' \
  Sources/MothApplication/MothCommandSystem.swift
grep -q 'M3A_PRODUCT_PHASE_CURRENT' README.md
grep -q 'M3A_EXECUTION_UPDATE_AFTER_C25J' docs/ROADMAP.md
grep -q 'M3A_DOCUMENT_SHEET_ARCHITECTURE' docs/ARCHITECTURE.md
grep -q 'MOTH_FIRST_LUNA_SUPPORT_POLICY' docs/LUNA_INTEGRATION.md

luna_base='862586d9762ed8529aac98313b205e4cf3e3fbfb'
luna_head="$(git -C Dependencies/Luna-UI rev-parse HEAD)"
git -C Dependencies/Luna-UI merge-base --is-ancestor "$luna_base" "$luna_head" || {
  echo 'error: Luna checkout is not descended from accepted C2.5H' >&2
  exit 1
}
while IFS= read -r changed; do
  [[ -z "$changed" || "$changed" == README.md || "$changed" == docs/* ]] || {
    printf 'error: M3A permits only Luna documentation changes, found: %s\n' "$changed" >&2
    exit 1
  }
done < <(git -C Dependencies/Luna-UI diff --name-only "$luna_base..$luna_head")
grep -q 'public struct LunaShellTab' \
  Dependencies/Luna-UI/Sources/LunaUI/LunaEditorShell.swift
grep -q 'public var hiddenTabIDs' \
  Dependencies/Luna-UI/Sources/LunaUI/LunaEditorShell.swift

swift test --filter MothM3ADocumentSheetTests
swift test --filter MothCommandSystemTests
swift test --filter MothApplicationTests
swift test --filter MothC25JPersistentInteractionTests
swift build
swift test
./scripts/validate-paired-iteration.sh
git diff --check

printf 'Moth M3A document-sheet integration validation passed.\n'
