# Codex 実装指示書 — 販売前P0修正（監査対応 / build16目標）

Codexへ: 以下は製品監査で確認された**販売前に直すべき不具合**の実装指示です。各項目は**実コードで根本原因を検証済み**。
`file:line` と受け入れ基準に従って実装し、`swift build` が通ること・各受け入れ基準を満たすことを確認してください。
作業ブランチ: `fix/p0-audit-accuracy-safety`（Claude Codeが起票済み・一部実装済み）。

対象リポ: `/Users/kurosuken/AIMacOptimizer`（worktree: `.claude/worktrees/prerelease-fixes`）

---

## ✅ 実装済み（Claude Code / このブランチ）— 変更しないこと、以降はこの上に積む

- **[P0-1a] 容量計算を物理割当サイズへ統一**
  - 追加: `Sources/Services/DiskSize.swift`（`totalFileAllocatedSize` ベースの共通ユーティリティ＋`volumeFreeBytes`）
  - 適用: `StorageAnalyzer.fileSize/directorySize/clearCacheMeasuringFreed`、`MemoryOptimizer.getDirectorySizeMB`
  - `clearCacheMeasuringFreed` は**ボリューム空き容量の増分**を第一指標に（フォールバックで物理サイズ差）
- **[P0-3] CoreSimulatorを一括修復から除外**（`DeepDiagnosisEngine.swift` 大型キャッシュ判定）: `CoreSimulator` は `isAutoFixable:false`＋個別削除を案内。
- **[P0-7a] DNS/フォントの偽効果を撤廃**（`SmartAdvisor.swift` #9）: `estimatedSavingMB=0`・`sizeMB=0`・数値非表示のメンテ情報項目に。

---

## 🔧 未実装（Codex担当）

### [P0-1b] 物理サイズ化の残り呼び出し箇所を掃討
- **根拠**: `attributesOfItem[.size]` / `.size` を使う容量計算が他にも残存し得る。`DiskSize` に寄せる。
- **作業**: 次で全件洗い出し、容量表示・削除見込みに使われる箇所を `DiskSize.allocatedMB/allocatedBytes` へ置換。
  ```
  grep -rn "attributesOfItem\|\.size\b\|fileSize" Sources/Services | grep -iE "size|byte|MB"
  ```
- **除外**: 表示専用でない一時計算や、意図的に論理サイズが必要な箇所（あればコメントで明記）。
- **受け入れ基準**: 32MB通常ファイル＋512MBスパースファイルを一時領域に作り、表示見込み ≒ 実削除量（±5%）になる。

### [P0-2] ブラウザキャッシュ: 集計と削除対象の不一致を解消
- **根拠（確認済み）**: `MemoryOptimizer.swift:270 getBrowserCacheInfo` は Chrome 3フォルダ / Safari 2フォルダを**合算**して見込み容量を出すが、`caches.append((..., chromeCachePaths[0], total))` と**先頭パスのみ**を保持。削除（`SmartAdvisor.swift:172` 系）は先頭1フォルダしか消さない → 表示 ≫ 実削除。
- **修正方針（推奨）**: アイテムに**全パスを保持**し、削除時に**全パスを削除**する（クリーニング効果を最大化）。モデル変更を避けたい場合の最小策は「見込みを先頭パスの実サイズだけにする」。
- **該当**: `MemoryOptimizer.swift:270-300`、削除実行 `SmartAdvisor.swift:172` 周辺。
- **受け入れ基準**: 表示した見込み容量＝実際に削除される合計容量。複数パス構成でも一致。

### [P0-7b] ワンクリック: 子項目の選択解除が親の見込みに反映されない
- **根拠（確認済み）**: `PopoverView.swift:2064` 付近、子(`detailItems`)の選択を外しても親提案の**全容量**を削除予定として表示。
- **修正**: 見込み容量を**選択中の子項目のみ**から再計算（`optimizePreview` 系のestimated計算を、`detailItems.filter{ $0.isSelected }` の物理サイズ合計に）。
- **受け入れ基準**: 子のチェックを外すと、予定容量がその分だけ即座に減る。

### [P0-4] Pro自動最適化の学習ループ・デッドロックを解消
- **根拠（確認済み）**: 自動実行の条件が「過去3回以上の最適化履歴」（`ScheduleManager.swift:119`）だが、**手動最適化が履歴に記録されない**（`PopoverView.swift:2165` は `PatternLearner.recordOptimized` を呼ばない/回数に加算しない）。回数が増えるのは自動実行時だけ → 最初の自動実行条件を満たせず**新規ユーザーは永久に自動化が始まらない**。
- **修正**: 手動最適化の完了時にも最適化回数を記録する（`PatternLearner` に最適化実行回数のカウンタを設け、手動/自動両方で加算）。または自動開始の初期条件を「履歴0でも既定しきい値で開始」に緩和。
- **該当**: `PatternLearner.swift:20`(記録) / `ScheduleManager.swift:119`(条件) / `PopoverView.swift:2165`(手動実行)。
- **受け入れ基準**: 新規ユーザーが手動最適化を数回行う→自動最適化が開始される。ユニット/手動手順で確認。

### [P0-7c] 保存されるが参照されない自動最適化しきい値を配線
- **根拠（確認済み）**: `SettingsView.swift:374` のしきい値は保存されるが、実サービス（`ScheduleManager`）が参照していない。
- **修正**: `ScheduleManager` の発火判定でこのしきい値（メモリ/容量）を読む。
- **受け入れ基準**: しきい値変更が自動最適化の発火に実際に反映される。

### [P0-5] メモリ診断をメモリプレッシャーベースへ
- **根拠（確認済み）**: メモリ診断が空き率中心。Appleは空き容量ではなくメモリプレッシャー（スワップ速度・キャッシュ・wired等の複合）で判断。単発計測でCPUスパイクを異常判定、大RSSを継続増加確認なしで「リーク候補」判定。
- **修正**:
  - メモリ: `host_statistics64` / `vm_statistics64`＋スワップ(ins/outs)から**メモリプレッシャー相当（緑/黄/赤）**を算出し判定に使う。「使用率80%＝悪」の断定通知をやめる。
  - CPU: 一度きりでなく**複数回サンプリング**の平均/継続で判定。
  - リーク候補: 大RSS単発ではなく**継続的増加**を確認できた場合のみ。
  - Info レベル項目は総合スコアを下げない。
  - Full Disk Access不足で走査できなかった領域を結果に明示。
- **受け入れ基準**: プレッシャー緑の高使用率状態で「危険」通知を出さない。黄/赤かつスワップ発生時のみ警告。

### [P0-6] Chromeタブ終了候補を安全側に
- **根拠（確認済み）**: `ChromeTabAnalyzer.swift:117` がログイン/OAuth/Google検索結果を「確実に閉じられる」と初期選択。タブ再オープンではフォーム入力/ページ内状態は復元不可。
- **修正**: ワンクリックの**初期選択は空タブ・完全重複のみ**。認証(OAuth/login)・検索結果ページは自動対象から除外（提案はしてもデフォルト未選択）。
- **受け入れ基準**: 認証/検索タブが初期状態で選択されていない。

### [P0-8] 診断・実行・週次レポートの永続化と、レポートの誤りを修正
- **根拠（確認済み）**: 再起動で直近レポート/診断が消える。週次レポートの「最も容量を食っている」は一部キャッシュ内比較、「先週比」は前週比較でなく直近7日の最初と最後の差、累積解放容量が残らない、再発日数が分からない。
- **修正**:
  - 診断結果・実行結果・週次レポートを永続化（UserDefaults/JSONファイル）。
  - 「先週比」を**実際の前週（-14〜-7日）と当週（-7〜0日）**の比較に。
  - 「最も容量」をキャッシュ内限定でなく妥当なスコープに。
  - **累積解放容量**を保存・表示。**同一問題の再発日数**を追跡。
- **受け入れ基準**: 再起動後もレポート/診断が残る。先週比が前週基準。累積解放が積算表示される。

### [P0-9] 以前の監査の積み残し
- ダウンロード版の不一致、ローカル昇格コード、LPとの機能差を確認し是正（別監査メモ参照）。

---

## 進め方・約束事
- 1項目=1コミット（日本語メッセージ）。`swift build` 成功を各コミット前に確認。
- **捏造値・実測不能な効果量を新たに足さない**（このメディア/製品の核は「実測で正直」）。
- 破壊的操作（一括削除）は必ず「対象の明示・復元可否・デフォルト未選択」を守る。
- 完了後、`fix/p0-audit-accuracy-safety` を push しPR更新。Claude Code が統合レビューします。

---

## （参考）コード以外の残作業 — 別途ハンドオフ済み
- **notarytool 再登録**: `~/Desktop/...`（`DELEGATE_TASKS.md`）
- **GSC ドメイン移行**: `~/Desktop/GSC移行手順_aimacoptimizer.md`
- **Claude Design 意匠作成**: `~/Desktop/ClaudeDesign_Mac実測ラボ/`
