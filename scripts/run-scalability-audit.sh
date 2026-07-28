#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
swift test --filter MothC25FVirtualizedDocumentTests
swift test --filter MothC25ERuntimeFairnessTests
swift test --filter MothC25D2PartialDamageTests
