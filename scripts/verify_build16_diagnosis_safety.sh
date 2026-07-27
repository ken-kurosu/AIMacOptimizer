#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-build16-diagnosis.XXXXXX)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

swiftc \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/DiagnosisBulkRepairPolicy.swift" \
    "$PROJECT_DIR/scripts/Build16DiagnosisSafetyVerifier.swift" \
    -o "$VERIFY_TMP/Build16DiagnosisSafetyVerifier"

"$VERIFY_TMP/Build16DiagnosisSafetyVerifier"

# 本番の一括修復経路が isAutoFixable のみを実行し、Simulator finding が
# isAutoFixable:false / action:noneになる配線を維持していることを確認する。
ENGINE="$PROJECT_DIR/AIMacOptimizer/Sources/Services/DeepDiagnosisEngine.swift"
rg -q 'filter \{ \$0\.isAutoFixable && \$0\.fixAction != \.none \}' "$ENGINE"
rg -q 'isAutoFixable: !isSimulator' "$ENGINE"
rg -q 'fixAction: isSimulator \? \.none' "$ENGINE"
