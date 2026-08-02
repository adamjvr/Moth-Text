#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  "Sources/MothApplication/MothPaneInteractionSnapshot.swift"
  "Sources/MothApplication/MothRuntimeWorkAttribution.swift"
  "Tests/MothApplicationTests/MothC25JPersistentInteractionTests.swift"
  "docs/C2.5J_PERSISTENT_INTERACTION_AND_DAMAGE.md"
  "packaging/linux/io.github.adamjvr.MothText.desktop"
  "packaging/linux/hicolor/256x256/apps/io.github.adamjvr.MothText.png"
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    printf 'error: missing C2.5J path: %s\n' "$path" >&2
    exit 1
  }
done

grep -q 'schemaVersion: Int = 4' \
  Sources/MothApplication/MothRuntimeWorkAttribution.swift
grep -q 'interactionSnapshotCacheHitCount' \
  Sources/MothApplication/MothRuntimeWorkAttribution.swift
grep -q 'paneInteractionSnapshotStore.cached' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'handleKeyboardWithMeasuredInvalidation' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'recordHostInvalidation' \
  Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'metadataLookupCount: plan.samples.count' \
  Sources/MothApplication/MothApplicationShellScene.swift

swift test --filter MothC25JPersistentInteractionTests
swift test --filter MothC25IInteractionSnapshotTests
swift test --filter MothC25HLargeDocumentPathTests
swift test --filter MothC25GRealShellAttributionTests
swift build
swift test
./scripts/validate-paired-iteration.sh
git diff --check

printf 'Moth C2.5J integration validation passed.\n'
