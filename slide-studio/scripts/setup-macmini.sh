#!/bin/bash
# Slide Studio を Mac mini(等)に常駐デプロイするワンショットスクリプト。
# 使い方(Mac mini のターミナルで):
#   curl -fsSL https://raw.githubusercontent.com/ken-kurosu/AIMacOptimizer/main/slide-studio/scripts/setup-macmini.sh | bash
# 2回目以降も同じコマンドで更新デプロイになる(コード取得→ビルド→再起動)。
#
# 環境変数で挙動を変えられる:
#   OPENAI_API_KEY      事前にexportしておくと入力プロンプトをスキップ
#   SLIDE_STUDIO_DIR    設置先(既定: ~/AIMacOptimizer)
set -euo pipefail

REPO="https://github.com/ken-kurosu/AIMacOptimizer.git"
DIR="${SLIDE_STUDIO_DIR:-$HOME/AIMacOptimizer}"
APP="$DIR/slide-studio"
PORT=3100

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "Node.js の確認"
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js が見つかりません。先に 'brew install node' を実行してください" >&2
  exit 1
fi
NODE_MAJOR=$(node -v | sed 's/^v\([0-9]*\).*/\1/')
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Node.js 20以上が必要です(現在: $(node -v))。'brew install node' で更新してください" >&2
  exit 1
fi
echo "node $(node -v) / npm $(npm -v)"

step "コードの取得"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch origin main
  git -C "$DIR" checkout main >/dev/null 2>&1 || true
  git -C "$DIR" pull --ff-only origin main
else
  git clone "$REPO" "$DIR"
fi
cd "$APP"

step "依存のインストール"
npm install --no-audit --no-fund

step "環境設定 (.env.local)"
if [ -f .env.local ]; then
  echo "既存の .env.local を使います"
else
  KEY="${OPENAI_API_KEY:-}"
  if [ -z "$KEY" ]; then
    printf "OpenAI APIキーを入力してください (sk-...): "
    read -rs KEY </dev/tty
    echo
  fi
  if [ -z "$KEY" ]; then
    echo "APIキーが空です。中断します" >&2
    exit 1
  fi
  TOKEN=$(openssl rand -hex 16)
  umask 077
  cat > .env.local <<ENV
OPENAI_API_KEY=$KEY
SLIDE_STUDIO_API_TOKEN=$TOKEN
ENV
  echo ".env.local を作成しました(アクセストークンを自動生成)"
fi
TOKEN=$(grep '^SLIDE_STUDIO_API_TOKEN=' .env.local | cut -d= -f2-)

step "本番ビルド"
npm run build

step "pm2 で常駐起動"
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2 --no-audit --no-fund
fi
pm2 startOrRestart scripts/ecosystem.config.cjs --update-env
pm2 save

step "ヘルスチェック"
sleep 3
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost:$PORT/api/export" || echo 000)
if [ "$CODE" != "200" ]; then
  echo "ヘルスチェックに失敗しました (HTTP $CODE)。'pm2 logs slide-studio' を確認してください" >&2
  exit 1
fi
NOAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/" || echo 000)
echo "認証あり: 200 / 認証なし: $NOAUTH (401なら保護が有効)"

HOST=$(hostname -s 2>/dev/null || hostname)
cat <<DONE

✅ デプロイ完了

  ブラウザ:   http://$HOST.local:$PORT/?token=$TOKEN
              (一度開けばCookieに保存され、以後トークン不要)
  AIka用設定: SLIDE_STUDIO_URL=http://$HOST.local:$PORT
              SLIDE_STUDIO_TOKEN=$TOKEN

  更新デプロイ: このスクリプトをもう一度実行するだけ
  ログ確認:     pm2 logs slide-studio
  Mac再起動後も自動起動するには(初回のみ): pm2 startup を実行し、表示されたsudoコマンドを実行

DONE
