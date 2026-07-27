#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-build16-auto.XXXXXX)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

swiftc \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Localization/Strings.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Models/ProcessInfo.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Models/UsagePattern.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/MemoryPressurePolicy.swift" \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/AutoOptimizationPolicy.swift" \
    "$PROJECT_DIR/scripts/Build16AutoPolicyVerifier.swift" \
    -o "$VERIFY_TMP/Build16AutoPolicyVerifier"

"$VERIFY_TMP/Build16AutoPolicyVerifier"

# 手動完了時の学習記録と、設定しきい値の読込が本番経路から外れていないことも確認する。
rg -q 'PatternLearner.shared.recordOptimized\(appName: appName\)' \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Views/PopoverView.swift"
rg -q 'autoOptimizeThresholdKey' \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/ScheduleManager.swift"
