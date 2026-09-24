#!/bin/bash
# 「メモリ使用量の多いアプリ」終了候補(方針A)を実機で試走し、安全性の不変条件を検証する。
# 読み取りのみ：UIは開かず、何も終了しない。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-heavyapp.XXXXXX)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

# トップレベルコードは main.swift にしか書けないため複製して渡す
cp "$PROJECT_DIR/scripts/HeavyAppCandidatesVerifier.swift" "$VERIFY_TMP/main.swift"

# App.swift(@main)以外の全ソース
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
    find "$PROJECT_DIR/AIMacOptimizer/Sources" -name '*.swift' ! -name 'App.swift' | sort
)

swiftc "${SOURCES[@]}" "$VERIFY_TMP/main.swift" -o "$VERIFY_TMP/HeavyAppCandidatesVerifier"
"$VERIFY_TMP/HeavyAppCandidatesVerifier"

# 方針A: 新枠は自動最適化(ScheduleManager)の対象外であること
grep -q 'where suggestion.type == .quitApp {' "$PROJECT_DIR/AIMacOptimizer/Sources/Services/ScheduleManager.swift"
# 方針A: 新枠の子項目は既定で未チェック・推奨なし
grep -q 'isSelected: false,      // 自動終了しない' "$PROJECT_DIR/AIMacOptimizer/Sources/Services/SmartAdvisor.swift"
grep -q 'isRecommended: false    // 推奨マークは付けない' "$PROJECT_DIR/AIMacOptimizer/Sources/Services/SmartAdvisor.swift"
echo "PASS: 新枠は自動最適化対象外・既定未チェック・推奨なし"
