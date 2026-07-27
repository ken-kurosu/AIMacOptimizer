# P0-9 / build16 販売前監査結果

実施日: 2026-07-27  
基準: `main` @ `3be7a23`  
対象: `fix/p0-9-and-build16`

## A. P0-9

### 1. ダウンロード版の不一致

- GitHub Releases の確認時点のlatestは `2.1.12 / build15`。実DMGの `Info.plist`、Developer ID署名、Apple公証を確認した。
- LPの一部CTAは固定URL `releases/download/v2.0.0/AIMacOptimizer-latest.dmg` のままで、実際には `2.1.11 / build14` を返していた。
- build16を `2.1.13 / build16` に更新した（`AIMacOptimizer/Info.plist:21-24`）。
- リリース生成は `Info.plist` を正本として読み、`latest.json` も同じ値から生成する（`scripts/build_dmg.sh:18-20,66-70`）。旧重複スクリプトは同スクリプトへの委譲にした。
- LPの修正箇所・公開順序は `docs/BUILD16_LP_HANDOFF.md` に記録した。公開後のDL URLは必ず `releases/latest/download/AIMacOptimizer-latest.dmg` とする。

### 2. ローカル昇格コード

- OS権限昇格API `AuthorizationExecuteWithPrivileges` / `SMJobBless` / `setuid` / `seteuid` は現ソースに該当なし。
- 旧監査の「昇格」はOS管理者権限ではなく、クライアント内の固定プロモコードと任意tier変更による **Pro権限昇格** を指していた。固定コード、`activatePromoCode`、`setTier`、関連UIを削除した。
- 現在は保存tier文字列を信用せず、署名済みキーまたは有効なオンライン猶予からのみtierを導出する（`LicenseManager.swift:120-142`）。
- `sudo tmutil` と広範な `rm -rf` を「安全」として一括コピーする案内も、実行コードではないが破壊的であるため撤廃した。

結論: OSのローカル権限昇格コードは元から該当なし。クライアント内Pro昇格経路とsudo案内は解消済み。

### 3. LPとの機能差

アプリ側の正本を次に統一した（`LicenseManager.swift:68-99`、`SettingsView.swift:168-178`）。

- Free: 現在の実測、手動整理、詳細診断、ローカル/オンデバイスAI相談、多言語。
- Pro: スケジュール自動最適化、自動ディスクガード、履歴・トレンド、詳細週次レポート。

旧週3回表示、FreeなのにロックされていたAI相談、FreeなのにPro扱いだった手動ストレージ整理を是正した。匿名操作統計は初期OFFの明示オプトインへ変更した（`AnalyticsService.swift:3-24`、`SettingsView.swift:705-715`）。

LP側には次の不一致が残るため、別リポで `docs/BUILD16_LP_HANDOFF.md` を適用する。

- 固定されたbuild14のDL URLと旧version表示。
- FreeのAI相談をPro項目にも重複掲載。
- 実装の裏付けがない「優先サポート」。
- 「全削除がゴミ箱経由」「外部送信0件」という過度な表現。
- FAQ/JSON-LDの旧Free/Pro境界。

## B. build16 最終検証

### 1. 表示容量 = 実解放量

`scripts/verify_build16_disk.sh` を実行。専用の一時APFSボリュームで検証し、ユーザーデータは使用していない。

- 通常ファイル: 論理 33,554,432 bytes / 物理 33,554,432 bytes
- 512MBスパース: 論理 536,870,912 bytes / 物理 16,384 bytes
- 表示予定合計: 33,570,816 bytes
- 削除後の実空き増加: 33,570,816 bytes
- 誤差: **0.00%（基準±5%以内）**

検証中、削除直後のURL容量値がキャッシュされて実増加を0と返す問題を検出したため、前後差は同期的な `statfs` を優先するよう修正した（`DiskSize.swift:54-70`）。

### 2. 安全な診断

`scripts/verify_build16_memory_policy.sh` を実行し、次を確認した。

- 使用率95%でもプレッシャー緑: 不発。
- 黄でもSwapなし: 不発。
- 黄/赤かつSwap発生、かつ設定しきい値以上: 発火。

診断、通知、自動最適化は共有の `MemoryPressurePolicy` を使用する。

### 3. Pro自動化

`scripts/verify_build16_auto_policy.sh` を実行し、次を確認した。

- 手動最適化2回: 自動化対象外。
- 手動最適化3回 + アイドル確度 > 0.7: 対象になる。
- プレッシャー緑、しきい値未満、普段使用する時間帯: 不発。
- 手動完了時の記録経路は `PopoverView.swift:2167-2189`、設定しきい値の発火配線は `ScheduleManager.swift:111-145`。

### 4. CoreSimulator保護

`scripts/verify_build16_diagnosis_safety.sh` を実行。CoreSimulatorと配下を手動対応必須と判定し、findingは `isAutoFixable:false / fixAction:none` になる（`DeepDiagnosisEngine.swift:388-405`）。「全て修復」は `isAutoFixable && action != none` のみ実行する（同:174-181）。

## ビルド結果

- `swift build`: 成功（exit 0）
- `swift build -c release`: 成功（exit 0）
- 上記4検証: すべて成功

## PR統合後に必要な外部作業

コード監査とローカル検証は完了。販売物の公開はPR統合後に次を行う。

1. `scripts/build_dmg.sh` でDeveloper ID署名・Apple公証・staple済みbuild16を生成。
2. GitHub ReleaseのDMGと`latest.json`を同時更新。
3. `docs/BUILD16_LP_HANDOFF.md`をLPリポへ適用。
4. 独立したMacでDL、Gatekeeper起動、Free/Pro購入キー、更新検知をスモーク確認。
