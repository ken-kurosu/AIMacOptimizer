#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-build16-memory.XXXXXX)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

swiftc \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Localization/Strings.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Models/ProcessInfo.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/MemoryPressurePolicy.swift" \
    "$PROJECT_DIR/scripts/Build16MemoryPolicyVerifier.swift" \
    -o "$VERIFY_TMP/Build16MemoryPolicyVerifier"

"$VERIFY_TMP/Build16MemoryPolicyVerifier"
