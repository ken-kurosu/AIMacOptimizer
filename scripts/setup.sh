#!/bin/bash
# CompDeck を 常駐サーバー(Mac等)に常駐デプロイするワンショットスクリプト。
# 使い方(サーバー のターミナルで):
#   curl -fsSL https://raw.githubusercontent.com/ken-kurosu/compdeck/main/scripts/setup.sh | bash
# 2回目以降も同じコマンドで更新デプロイになる(コード取得→ビルド→再起動)。
#
# 環境変数で挙動を変えられる:
#   OPENAI_API_KEY      事前にexportしておくと入力プロンプトをスキップ
#   COMPDECK_DIR    設置先(既定: ~/compdeck)
set -euo pipefail

REPO="https://github.com/ken-kurosu/compdeck.git"
DIR="${COMPDECK_DIR:-$HOME/compdeck}"
APP="$DIR"
PORT=3100

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "Node.js の確認"
# 非対話SSH経由だとHomebrew等のPATHが通っていないため、よくある場所を補完する
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
if ! command -v node >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
fi
if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Node.js が見つからないため Homebrew でインストールします(数分かかります)"
    brew install node
  else
    echo "Node.js も Homebrew も見つかりません。サーバー で https://brew.sh の手順でHomebrewを入れてから再実行してください" >&2
    exit 1
  fi
fi
NODE_MAJOR=$(node -v | sed 's/^v\([0-9]*\).*/\1/')
if [ "$NODE_MAJOR" -lt 20 ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Node.js 20以上が必要です(現在: $(node -v))。Homebrewで更新します"
    brew install node && brew link --overwrite node
  else
    echo "Node.js 20以上が必要です(現在: $(node -v))" >&2
    exit 1
  fi
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
COMPDECK_API_TOKEN=$TOKEN
ENV
  echo ".env.local を作成しました(アクセストークンを自動生成)"
fi
TOKEN=$(grep '^COMPDECK_API_TOKEN=' .env.local | cut -d= -f2-)

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
  echo "ヘルスチェックに失敗しました (HTTP $CODE)。'pm2 logs compdeck' を確認してください" >&2
  exit 1
fi
NOAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/" || echo 000)
echo "認証あり: 200 / 認証なし: $NOAUTH (401なら保護が有効)"

HOST=$(hostname -s 2>/dev/null || hostname)
cat <<DONE

✅ デプロイ完了

  ブラウザ:   http://$HOST.local:$PORT/?token=$TOKEN
              (一度開けばCookieに保存され、以後トークン不要)
  Slackエージェント用設定: COMPDECK_URL=http://$HOST.local:$PORT
              COMPDECK_TOKEN=$TOKEN

  更新デプロイ: このスクリプトをもう一度実行するだけ
  ログ確認:     pm2 logs compdeck
  Mac再起動後も自動起動するには(初回のみ): pm2 startup を実行し、表示されたsudoコマンドを実行

DONE
