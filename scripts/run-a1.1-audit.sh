#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${MOTH_A1_OUTPUT_DIR:-.build/a1.1-audit}"
mkdir -p "$OUTPUT_DIR"

MOTH_RUN_A1_FULL_AUDIT=1 \
MOTH_A1_OUTPUT_DIR="$OUTPUT_DIR" \
swift test --filter MothA1AuditTests/testFullAuditMatrixWhenExplicitlyEnabled

printf '\nA1.1 Moth audit written to: %s\n' "$OUTPUT_DIR"
