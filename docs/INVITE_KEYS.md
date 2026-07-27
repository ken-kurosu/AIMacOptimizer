# 招待キー（Proライセンスキー）の発行方法

build16でハードコードの固定プロモコード（`AIMAC-FRIENDS-2026` 等）は廃止しました。
Proの付与・招待は、秘密鍵で**署名した偽造不可のライセンスキー**で行います。アプリは埋め込んだ公開鍵でオフライン検証します（サーバー不要・無料）。

## 発行コマンド

秘密鍵 `~/.aimac_license_private_key`（このMacに保管・`chmod 600`）を使って発行します。

```bash
cd ~/AIMacOptimizer

# 友人・チーム・身内の招待（無期限のPro買い切り相当）
swift scripts/sign_license.swift
# → プラン: Pro (Lifetime・無期限)
#   AIMAC-........（この行を相手に渡す）

# 月額Pro相当（今日から35日・更新猶予込み）
swift scripts/sign_license.swift monthly

# ベータ招待（既定90日／日数指定可）
swift scripts/sign_license.swift beta        # 90日
swift scripts/sign_license.swift beta 60     # 60日
```

出力された `AIMAC-...` の1行を相手に渡します。

## 受け取った人の使い方

アプリの **設定 → ライセンス → ライセンスキー** に貼り付けて有効化。
即座にProになります（オフラインで署名検証。ネット不要）。

## 使い分けの目安

| 相手 | コマンド | 期限 |
|---|---|---|
| 友人・家族・チームメンバー・登壇/献本 | `sign_license.swift` | 無期限 |
| 期間限定のお試し提供 | `sign_license.swift monthly` | 35日 |
| ベータテスター | `sign_license.swift beta [日数]` | 指定日数（既定90日） |

## 注意

- **秘密鍵は絶対に共有・コミットしない**（`~/.aimac_license_private_key` のみが発行源）。漏れると誰でもProキーを作れてしまう。
- 無期限キーは事実上ずっと有効。乱発しない（配布数は購入導線とのバランスで管理）。
- 有料購入の自動発行は Cloudflare Worker（`server/license-webhook/`）が同じ署名形式で行う。本スクリプトは**手動招待用**。
- 署名形式の正本: `AIMacOptimizer/Sources/Services/SignedLicense.swift`（v2: version/tier/expiry/nonce, Ed25519）。
