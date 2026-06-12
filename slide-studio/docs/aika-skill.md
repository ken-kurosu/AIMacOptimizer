# AIka(Slackエージェント)用 スライド作成スキル

slide-studio をAIka経由で使うためのドロップイン資料。
aika-slack-agent リポジトリにスキルとして追加する想定。

## 前提

- slide-studio が Mac mini で常時起動していること(下記「デプロイ」参照)
- AIka の環境変数に以下を設定:
  - `SLIDE_STUDIO_URL` 例: `http://mac-mini.local:3100`
  - `SLIDE_STUDIO_TOKEN` slide-studio 側の `SLIDE_STUDIO_API_TOKEN` と同じ値

## 会話フロー

1. ユーザー「◯◯のスライド作って」
2. AIka が要件(内容・ページ数)を整理して **構成案を作成** → Slackに整形して投稿し、OK/修正を聞く
3. 修正コメントが来たら feedback を付けて構成案を作り直し(何往復でも)
4. **goが出たら生成**(3〜10分かかるので「作ってます」と先に返す) → 完成したら **編集URLを投稿**

## API

```python
import requests

BASE = os.environ["SLIDE_STUDIO_URL"]
HEADERS = {
    "Authorization": f"Bearer {os.environ['SLIDE_STUDIO_TOKEN']}",
    "Content-Type": "application/json",
}

def make_plan(topic: str, pages: int = 6, feedback: str | None = None, previous_plan: dict | None = None) -> dict:
    """構成案を作る(修正時は feedback + previous_plan を渡す)。60-90秒。"""
    r = requests.post(f"{BASE}/api/generate/plan", headers=HEADERS, json={
        "topic": topic, "pages": pages,
        "feedback": feedback, "previousPlan": previous_plan,
    }, timeout=180)
    r.raise_for_status()
    return r.json()["plan"]

def create_deck(plan: dict) -> dict:
    """承認済みの構成案から生成して保存。1ページ約1分。
    返り値: { id, editUrl, title, pages } — editUrl をSlackに投稿する(認証トークン込み)"""
    r = requests.post(f"{BASE}/api/decks", headers=HEADERS, json={"plan": plan}, timeout=900)
    r.raise_for_status()
    return r.json()
```

## 構成案のSlack整形例

```python
def format_plan(plan: dict) -> str:
    lines = [f"*{plan['title']}* ({len(plan['pages'])}ページ) の構成案です:"]
    for i, p in enumerate(plan["pages"], 1):
        texts = "、".join(t["text"] for t in p.get("texts", [])[:3])
        lines.append(f"{i}. *{p['name']}* — {texts}")
    lines.append("この構成でよければ「OK」、直したい点があればそのまま教えてください")
    return "\n".join(lines)
```

## 注意

- 生成は長い(3〜10分)。`create_deck` は先に「生成を始めました(◯分くらい)」と返してから呼ぶ
- `editUrl` には閲覧用トークンが含まれる。社内チャンネル以外には貼らない
- エラー時は `r.json()["error"]` に日本語の理由が入っている

## slide-studio のデプロイ(Mac mini)

```bash
git clone https://github.com/ken-kurosu/AIMacOptimizer.git
cd AIMacOptimizer/slide-studio
npm install && npm run build

# 起動(例: pm2)
npm install -g pm2
OPENAI_API_KEY=sk-... \
SLIDE_STUDIO_API_TOKEN=長いランダム文字列 \
PORT=3100 \
pm2 start npm --name slide-studio -- start
pm2 save && pm2 startup   # 再起動後も自動起動
```

- Chrome がインストールされていれば PDF書き出し・批評ループも自動で有効
- 生成物は `slide-studio/.assets/` に保存される(ディスクに余裕を)
- 社内からは `http://<mac-miniのホスト名>.local:3100/?token=<トークン>` を一度開けば以後トークン不要
