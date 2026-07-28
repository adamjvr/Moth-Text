#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
  Sources/MothApplication/MothRuntimeWorkAttribution.swift
  Sources/MothApplication/MothDocumentViewportPresentationStore.swift
  Sources/MothApplication/MothMinimapSamplePlan.swift
  Sources/MothApplication/MothApplicationShellScene.swift
  Tests/MothApplicationTests/MothC25ERuntimeFairnessTests.swift
  Tests/MothApplicationTests/MothC25FVirtualizedDocumentTests.swift
  Tests/MothApplicationTests/MothC25GRealShellAttributionTests.swift
  scripts/update-luna-exact.sh
  docs/C2.5G_MEASURED_PRESENTATION_INTEGRATION.md
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "error: missing $path" >&2; exit 1; }
done

grep -Fq 'runtimeAttributionRecorder' Sources/MothApplication/MothApplicationShellScene.swift
grep -Fq 'currentViewportPresentation' Sources/MothApplication/MothApplicationShellScene.swift
grep -Fq 'virtualizationContext' Sources/MothApplication/MothPaneEditorSurface.swift
grep -Fq 'MothMinimapSamplePlan' Sources/MothApplication/MothApplicationShellScene.swift

git submodule status --recursive
swift test --filter MothC25ERuntimeFairnessTests
swift test --filter MothC25FVirtualizedDocumentTests
swift test --filter MothC25GRealShellAttributionTests
swift build
swift test
./scripts/validate-paired-iteration.sh
git diff --check
