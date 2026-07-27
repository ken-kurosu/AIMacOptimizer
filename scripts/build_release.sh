#!/bin/bash
# 互換用エントリーポイント。
# バージョン、署名、公証、latest.json生成の正本は build_dmg.sh に一本化する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/build_dmg.sh" "$@"
