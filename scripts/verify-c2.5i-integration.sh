#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

required=(
  "Sources/MothApplication/MothPaneInteractionSnapshot.swift"
  "Tests/MothApplicationTests/MothC25IInteractionSnapshotTests.swift"
  "docs/C2.5I_INTERACTION_SNAPSHOT_AND_ICON.md"
  "packaging/linux/io.github.adamjvr.MothText.desktop"
  "packaging/linux/install-user.sh"
  "packaging/linux/uninstall-user.sh"
  "packaging/linux/hicolor/256x256/apps/io.github.adamjvr.MothText.png"
  "Assets/icons/moth-text-1024.png"
  "Assets/icons/moth-text-original-cleaned.png"
)

for path in "${required[@]}"; do
    [[ -f "${path}" ]] || {
        printf 'error: missing C2.5I path: %s\n' "${path}" >&2
        exit 1
    }
done

grep -q 'schemaVersion: Int = 3' \
    Sources/MothApplication/MothRuntimeWorkAttribution.swift
grep -q 'makePaneInteractionSnapshot' \
    Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'presentationBundle: framePresentation' \
    Sources/MothApplication/MothApplicationShellScene.swift
grep -q 'metadataLookupCount: plan.samples.count' \
    Sources/MothApplication/MothApplicationShellScene.swift

swift test --filter MothC25IInteractionSnapshotTests
swift build
swift test
./scripts/validate-paired-iteration.sh
git diff --check

printf 'Moth C2.5I integration validation passed.\n'
