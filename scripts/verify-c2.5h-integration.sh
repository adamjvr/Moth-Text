#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
required=(
  Sources/MothApplication/MothRuntimeWorkAttribution.swift
  Sources/MothApplication/MothApplicationShellScene.swift
  Tests/MothApplicationTests/MothC25HLargeDocumentPathTests.swift
  docs/C2.5H_LARGE_DOCUMENT_PATH.md
)
for path in "${required[@]}"; do test -f "$path" || { echo "error: missing $path" >&2; exit 1; }; done
grep -Fq 'lineMetadata(' Sources/MothApplication/MothApplicationShellScene.swift
grep -Fq 'minimapMetadataLookupCount' Sources/MothApplication/MothRuntimeWorkAttribution.swift
grep -Fq 'public func lineMetadata(at index: Int)' Dependencies/Luna-UI/Sources/LunaUI/LunaStaticTextView.swift
(
  cd Dependencies/Luna-UI
  swift test --filter LunaC25HLazyLineIndexTests
)
swift test --filter MothC25HLargeDocumentPathTests
swift test --filter MothC25ERuntimeFairnessTests
swift test --filter MothC25FVirtualizedDocumentTests
swift test --filter MothC25GRealShellAttributionTests
swift build
swift test
./scripts/validate-paired-iteration.sh
git diff --check
