# AI Mac Optimizer

macOS メニューバーから、メモリとストレージをAIで賢く最適化するアプリ。
11種類のAI最適化エンジンが、あなたのMacをリアルタイムで分析・最適化します。

## 機能（v2.0）

**メモリ最適化（11種類のAI分析）**
- リアルタイムメモリ監視（ゲージ表示）
- プロセス別メモリ使用量ランキング
- Chromeタブ自動分析（重複・未使用タブ検出）
- Safariタブ自動分析（AppleScript経由）
- バックグラウンドアプリ終了提案
- メモリリーク候補のアプリ再起動提案
- ブラウザキャッシュ削除（Chrome / Safari / Firefox / Arc）
- Chrome拡張機能メモリ分析
- ログイン項目（自動起動アプリ）の検出・管理
- 一時ファイル・ゴミ箱クリーンアップ
- DNS / フォントキャッシュフラッシュ
- Swap使用量の警告・対策提案
- RAMキャッシュパージ（ワンクリック）

**ストレージ分析**
- キャッシュ・ログファイル検出
- 古いインストーラー（DMG/PKG）検出
- 大容量ファイル検出（500MB以上）
- 安全な削除（確認ダイアログ付き・サブファイル単位で選択可能）
- iCloud移行オプション

**ディスク自動ガード**
- ディスク使用状況を定期監視（既定: 使用率90%以上 or 空き10GB未満で「圧迫」と判定／設定で調整可）
- 圧迫時に、リスクのないキャッシュ/ログのみを「安全に空ける」プランとして提案（何を消すか・安全度・理由・回収量を明記、フォントキャッシュ等は自動保護）
- ワンボタンで安全に空ける。承認時に「今後は自動で空ける（通知のみ）」へ切替可能
- 再提案/再削除は3時間クールダウンで抑制

**AIアシスタント（相談）**
- **ローカル解析（既定・無料・キー不要・オフライン）**: 診断レポートの実測値に基づき、メモリ/ディスク/起動/CPU/バッテリーの具体的な改善を案内
- **オンデバイスAI（無料）**: Apple Foundation Models 対応の Mac では自由対話も無料（非対応環境はローカル解析に自動フォールバック）
- **上級モード（任意）**: OpenAI / Anthropic の API キーを設定すると、より自由な対話が可能（従量課金・キーは Keychain 保存）

**AI学習**
- 使用パターンの学習・アイドルアプリ自動判定
- 使うほど賢くなる最適化提案
- スケジュール自動最適化（アイドル時実行）
- 静かな時間帯設定

**その他**
- 多言語対応（日本語 / English / 中文）
- メニューバー常駐（Dock非表示）
- macOS 13 Ventura 以降対応

## 技術スタック

- **言語**: Swift 5.9
- **UI**: SwiftUI (MenuBarExtra)
- **対応**: macOS 13+ / Apple Silicon & Intel
- **ビルド**: Swift Package Manager

## プロジェクト構成

```
AIMacOptimizer/
├── Package.swift
├── AIMacOptimizer/
│   ├── Sources/
│   │   ├── App.swift                    # エントリーポイント
│   │   ├── Models/
│   │   │   ├── ProcessInfo.swift        # プロセス・メモリ情報
│   │   │   ├── ChromeTab.swift          # Chromeタブ・提案モデル
│   │   │   ├── StorageInfo.swift        # ストレージデータモデル
│   │   │   └── UsagePattern.swift       # AI学習データモデル
│   │   ├── Services/
│   │   │   ├── ProcessMonitor.swift     # プロセス監視
│   │   │   ├── ChromeTabAnalyzer.swift  # Chromeタブ分析
│   │   │   ├── MemoryOptimizer.swift    # メモリ最適化実行
│   │   │   ├── SmartAdvisor.swift       # 最適化提案エンジン
│   │   │   ├── StorageAnalyzer.swift    # ストレージ分析
│   │   │   ├── PatternLearner.swift     # AI学習エンジン
│   │   │   └── ScheduleManager.swift    # スケジュール管理
│   │   ├── Views/
│   │   │   ├── PopoverView.swift        # メインポップオーバー
│   │   │   └── SettingsView.swift       # 設定画面
│   │   └── Localization/
│   │       └── Strings.swift            # 多言語文字列
│   ├── Resources/
│   │   └── AppIcon.svg
│   ├── Info.plist
│   └── AIMacOptimizer.entitlements
└── scripts/
    ├── build_release.sh                 # リリースビルド
    └── generate_icon.sh                 # アイコン変換
```

## ビルド方法

### Xcodeで開く
```bash
open AIMacOptimizer/Package.swift
```
Xcode で `⌘R` を押して実行。

### コマンドラインビルド
```bash
swift build -c release
```

## リリースビルド
```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```
`build/` ディレクトリに `.app` と `.dmg` が生成されます。

## 必要な権限

- **オートメーション** (com.google.Chrome): Chromeタブ分析に必要
- **オートメーション** (com.apple.Safari): Safariタブ分析に必要
- **フルディスクアクセス**: ストレージ分析・キャッシュ削除に必要
- **通知**: スケジュール最適化の結果通知に使用

## 料金プラン

| | Free | Pro | Pro Lifetime |
|---|---|---|---|
| 価格 | ¥0 | ¥480/月（¥3,980/年） | ¥4,980（買い切り） |
| メモリ分析 | ○ | ○ | ○ |
| Chromeタブ分析 | ○ | ○ | ○ |
| ストレージスキャン | 表示のみ | 削除実行可 | 削除実行可 |
| AI提案 | 3回/週 | 無制限 | 無制限 |
| スケジュール | - | ○ | ○ |
| 多言語 | - | ○ | ○ |

## ライセンス

All rights reserved. © 2026
