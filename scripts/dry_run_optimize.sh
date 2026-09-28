#!/bin/bash
# ワンクリック最適化の試走（読み取りのみ）。このMacで今「AI最適化提案」に何が出て、
# ボタンを押すと何が実行されるかを表示する。何も終了・削除しない。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-dryrun.XXXXXX)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

cp "$PROJECT_DIR/scripts/DryRunOptimizeVerifier.swift" "$VERIFY_TMP/main.swift"
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
    find "$PROJECT_DIR/AIMacOptimizer/Sources" -name '*.swift' ! -name 'App.swift' | sort
)
swiftc "${SOURCES[@]}" "$VERIFY_TMP/main.swift" -o "$VERIFY_TMP/DryRunOptimize" 2>/dev/null
"$VERIFY_TMP/DryRunOptimize"
