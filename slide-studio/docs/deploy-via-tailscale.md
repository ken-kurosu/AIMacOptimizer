# Tailscale経由で Mac mini へリモートデプロイする手順(Claude Codeセッション用)

Claude Code on the web のセッションから、テイルネット内の Mac mini に slide-studio を
デプロイするためのランブック。環境のネットワークポリシーに以下が許可されている前提:
`*.tailscale.com` / `pkgs.tailscale.com`(+ デフォルトのパッケージマネージャー群)。

## 手順

### 1. コンテナにTailscaleを入れて起動(ユーザースペースモード)

```bash
# 最新版のファイル名は https://pkgs.tailscale.com/stable/ の一覧で確認
curl -fsSL https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz -o /tmp/ts.tgz
tar xzf /tmp/ts.tgz -C /tmp
cp /tmp/tailscale_*_amd64/tailscale /tmp/tailscale_*_amd64/tailscaled /usr/local/bin/

# コンテナにはTUNが無いのでユーザースペースネットワーキング+SOCKS5で起動
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 \
  --statedir=/tmp/tailscale-state > /tmp/tailscaled.log 2>&1 &
sleep 2
tailscale up --hostname=claude-deploy --accept-routes
```

`tailscale up` が表示する `https://login.tailscale.com/a/...` の認証URLを
**そのままユーザーに見せて、ブラウザで承認してもらう**(承認されるまでコマンドはブロックする)。

### 2. Mac mini への到達確認

ユーザーに Mac mini の Tailscale マシン名(または100.x.y.zのIP)と、
SSHユーザー名を確認する。Mac mini側は「システム設定 > 一般 > 共有 > リモートログイン」がON。

```bash
tailscale status                  # マシン一覧にmac miniが見えるか
tailscale ping <mac-miniの名前>   # 到達確認
```

SSH認証は次のどちらか:
- このコンテナで `ssh-keygen -t ed25519` して公開鍵をユーザーに渡し、
  Mac mini の `~/.ssh/authorized_keys` に追記してもらう(推奨)
- またはユーザーからパスワードを受け取り `sshpass` を使う(終わったら変更を推奨)

### 3. デプロイ実行

ユーザースペースモードなので SSH は SOCKS5 経由にする:

```bash
ssh -o ProxyCommand="/usr/local/bin/tailscale nc %h %p" \
    -o StrictHostKeyChecking=accept-new \
    <ユーザー名>@<mac-miniの名前> \
    "OPENAI_API_KEY=$OPENAI_API_KEY bash -c 'curl -fsSL https://raw.githubusercontent.com/ken-kurosu/AIMacOptimizer/main/slide-studio/scripts/setup-macmini.sh | bash'"
```

(OPENAI_API_KEY はコンテナの環境変数に入っているのでそのまま渡す)

成功すると最後に以下が表示されるので、**SLIDE_STUDIO_URL と SLIDE_STUDIO_TOKEN をユーザーへ報告**:

```
✅ デプロイ完了
  ブラウザ:   http://<ホスト名>.local:3100/?token=...
  AIka用設定: SLIDE_STUDIO_URL=... / SLIDE_STUDIO_TOKEN=...
```

### 4. 動作確認と後始末

```bash
# Tailscale越しのヘルスチェック(トークンはMac miniの slide-studio/.env.local 参照)
curl -s --socks5-hostname localhost:1055 \
  -H "Authorization: Bearer <トークン>" http://<mac-miniの名前>:3100/api/export
# → {"available":true} ならPDF書き出しまで有効

tailscale logout   # コンテナの一時ノードをテイルネットから外す
```

最後にユーザーへ: Tailscale管理画面に `claude-deploy` ノードが残っていたら削除してよい、と伝える。

## トラブルシュート

- `tailscale up` がタイムアウト → DERP(443)もポリシーで塞がれている。`*.tailscale.com` の許可を確認
- SSH拒否 → Mac miniのリモートログインON、ユーザー名、authorized_keys を確認
- ビルドでメモリ不足 → Mac mini の他プロセスを止めて再実行(スクリプトは冪等)
