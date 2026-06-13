# AIka(Slackエージェント)用 スライド作成スキル — 実装依頼書

slide-studio をAIka経由で使うためのドロップイン資料。aika-slack-agent リポジトリに
スキルとして追加する想定。**このドキュメント単体で実装が完結する**ように書いてあるので、
AIka側の開発セッションには次のように依頼すればよい:

> スライド作成スキルを追加して。仕様はこれ:
> https://raw.githubusercontent.com/ken-kurosu/AIMacOptimizer/main/slide-studio/docs/aika-skill.md
> SLIDE_STUDIO_URL と SLIDE_STUDIO_TOKEN は環境変数に設定済み(値は別途渡す)

## 前提

- slide-studio が Mac mini で常時起動していること(下記「デプロイ」参照)
- AIka の環境変数に以下を設定:
  - `SLIDE_STUDIO_URL` 例: `http://mac-mini.local:3100`
  - `SLIDE_STUDIO_TOKEN` slide-studio 側の `SLIDE_STUDIO_API_TOKEN` と同じ値

## 会話フロー

1. ユーザー「◯◯のスライド作って」
2. AIka が要件(内容・ページ数)を整理して **構成案を作成** → Slackに整形して投稿し、OK/修正を聞く
3. 修正コメントが来たら feedback を付けて構成案を作り直し(何往復でも)
4. **goが出たら生成**(10〜30分かかるので「作ってます」と先に返す) → 完成したら **編集URLを投稿**
   (生成されたデッキは各ページが「背景+動かせるモチーフレイヤー+テキスト」に分解済みで届く)

## API

```python
import requests

BASE = os.environ["SLIDE_STUDIO_URL"]
HEADERS = {
    "Authorization": f"Bearer {os.environ['SLIDE_STUDIO_TOKEN']}",
    "Content-Type": "application/json",
}

def make_plan(topic: str, pages: int | None = None, feedback: str | None = None, previous_plan: dict | None = None) -> dict:
    """構成案を作る(修正時は feedback + previous_plan を渡す)。1〜2分(research付きは+1分程度)。
    pages は省略するとAIが内容量から適切な枚数を提案する(ユーザーが枚数を指定した時だけ渡す)。
    research=True を渡すと、構成前にWeb検索で事実(料金・実績・正式名称)を集めて反映する(+30-60秒)。
    レスポンスの sources(参照URL一覧)はSlackの構成案投稿に添えるとよい。"""
    r = requests.post(f"{BASE}/api/generate/plan", headers=HEADERS, json={
        "topic": topic, "pages": pages, "research": True,
        "feedback": feedback, "previousPlan": previous_plan,
    }, timeout=300)
    r.raise_for_status()
    return r.json()["plan"]

def create_deck(plan: dict) -> dict:
    """承認済みの構成案から生成して保存。1ページ約2〜3分、8ページなら20分前後
    (デザイン生成+品質検査+編集用レイヤーへの自動分解まで含む)。
    返り値: { id, editUrl, title, pages } — editUrl をSlackに投稿する(認証トークン込み)"""
    r = requests.post(f"{BASE}/api/decks", headers=HEADERS, json={"plan": plan}, timeout=1800)
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

## APIリファレンス(このスキルが使うもの)

| エンドポイント | 用途 | 所要時間 |
|---|---|---|
| `POST /api/generate/plan` | 構成案の作成・修正(`topic`,`pages`任意で`feedback`+`previousPlan`) | 1〜2分 |
| `POST /api/decks` | `{"plan": <承認済みplan>}` で生成+保存 → `{id, editUrl, title, pages}` | 1ページ約2〜3分 |
| `GET /api/decks` | 保存済みデッキ一覧(「前作ったやつ開いて」用) | 即時 |

- 認証は全エンドポイント `Authorization: Bearer <SLIDE_STUDIO_TOKEN>`
- エラー時は `{"error": "<日本語の理由>"}` が返る(HTTPは400/401/502)
- planの構造: `{title, theme:{colors,...}, pages:[{name, motif, space, imagePrompt, texts:[{role,text}]}]}`
  修正再依頼ではこれを `previousPlan` としてそのまま返す(会話の状態として保持しておく)

## 会話設計の注意

- 生成は長い(10〜30分)。`create_deck` は先に「生成を始めました(◯分くらい)」と返してから呼ぶ。目安は ページ数×2.5分
- 構成案はユーザーが修正を何往復もできる。直前のplanを会話状態に保持し、
  修正コメントはそのまま `feedback` に渡す(解釈しすぎない)
- `editUrl` には閲覧用トークンが含まれる。社内チャンネル以外には貼らない
- タイムアウトは plan: 300秒 / decks: 1800秒 を目安に

## 完了チェックリスト

- [ ] 「◯◯のスライド作って」→ 構成案がSlackに整形されて出る
- [ ] 「2ページ目を△△にして」→ 修正された構成案が出る
- [ ] 「OK」→ 「生成中(◯分)」の応答 → 完成後に editUrl が投稿される
- [ ] editUrl をクリックすると編集画面が開く(トークン込みなので認証不要)
- [ ] slide-studio停止時など、エラーが日本語でユーザーに伝わる

## slide-studio のデプロイ(Mac mini)

Mac mini のターミナルでこの1行を実行するだけ(初回はOpenAI APIキーの入力を求められます):

```bash
curl -fsSL https://raw.githubusercontent.com/ken-kurosu/AIMacOptimizer/main/slide-studio/scripts/setup-macmini.sh | bash
```

スクリプトが「コード取得 → npm install → 本番ビルド → アクセストークン自動生成 →
pm2常駐起動(ポート3100) → ヘルスチェック」まで行い、最後に **ブラウザ用URLと
AIka用の SLIDE_STUDIO_URL / SLIDE_STUDIO_TOKEN** を表示します。
更新デプロイも同じ1行を再実行するだけです。

- 前提: Node.js 20+(`brew install node`)。Chrome があれば PDF書き出し・批評ループも自動で有効
- 生成物は `slide-studio/.assets/` に保存される(ディスクに余裕を)
- Mac再起動後の自動起動は初回のみ `pm2 startup` を実行し、表示されるsudoコマンドを実行
