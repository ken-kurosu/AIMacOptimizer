import Foundation

/// API もキーも使わず、診断レポートの実測データに基づいて回答を組み立てる
/// ローカルのルール/テンプレートエンジン（無料・オフライン・プライバシー保護）。
///
/// Mac 最適化という有限な問題領域では、実測値に直結したこの方式の方が
/// 汎用 LLM より外さない回答を返せる。自由対話の柔軟性のみトレードオフ。
struct LocalAdvisor {
    static let shared = LocalAdvisor()

    /// 質問の意図カテゴリ
    private enum Intent {
        case memory, disk, battery, startup, cpu, overview, cleanup
    }

    /// 質問とレポートから回答を生成
    func answer(question: String, report: DiagnosisReport?) -> String {
        guard let report = report else {
            return """
            まず「Deep Diagnosis（詳細診断）」を実行してください。
            実測データに基づいて、メモリ・ディスク・起動項目などの具体的な改善点をご案内します。
            """
        }

        switch classify(question) {
        case .memory:   return memoryAnswer(report)
        case .disk:     return diskAnswer(report)
        case .battery:  return batteryAnswer(report)
        case .startup:  return startupAnswer(report)
        case .cpu:      return cpuAnswer(report)
        case .cleanup:  return cleanupAnswer(report)
        case .overview: return overviewAnswer(report)
        }
    }

    // MARK: - 意図分類（キーワードベース）

    private func classify(_ q: String) -> Intent {
        let s = q.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { s.contains($0) } }

        if has(["メモリ", "memory", "ram", "圧迫", "スワップ", "swap"]) { return .memory }
        if has(["ディスク", "disk", "容量", "ストレージ", "空き", "storage", "空容量"]) { return .disk }
        if has(["バッテリー", "battery", "充電", "電池"]) { return .battery }
        if has(["起動", "ログイン項目", "startup", "login", "自動起動", "立ち上が"]) { return .startup }
        if has(["cpu", "発熱", "ファン", "負荷", "熱い"]) { return .cpu }
        if has(["掃除", "削除", "クリーン", "キャッシュ", "片付", "cleanup", "空け"]) { return .cleanup }
        if has(["重い", "遅い", "もっさり", "slow", "重く", "改善", "最適化", "どうすれば", "何をすれば"]) { return .overview }
        return .overview
    }

    // MARK: - 各カテゴリの回答

    private func memoryAnswer(_ r: DiagnosisReport) -> String {
        let s = r.systemSnapshot
        let usedPct = s.totalRAM_MB > 0 ? Int(Double(s.usedRAM_MB) / Double(s.totalRAM_MB) * 100) : 0
        var out = ["【メモリの状況】",
                   "・使用 \(formatMB(s.usedRAM_MB)) / 全体 \(formatMB(s.totalRAM_MB))（約\(usedPct)%）",
                   "・圧縮メモリ \(formatMB(s.compressedRAM_MB))、スワップ \(formatMB(s.swapUsedMB))"]
        if s.swapUsedMB > 2048 {
            out.append("⚠️ スワップが多めです。物理メモリが不足しがちで、ディスク経由の読み書きが増えて体感が遅くなります。")
        }
        if !s.topProcesses.isEmpty {
            out.append("")
            out.append("【メモリを多く使っているアプリ】")
            out.append(contentsOf: s.topProcesses.prefix(3).map { "・\($0)" })
        }
        out.append(contentsOf: findingsBlock(r, category: .memory))
        out.append("")
        out.append("【おすすめの対処】")
        out.append("1. 使っていない上位アプリを終了（メモリタブからワンクリック可）")
        out.append("2. メモリタブの「RAMパージ」で解放")
        out.append("3. ブラウザのタブが多ければ整理（タブ分析で重複・未使用を検出できます）")
        return out.joined(separator: "\n")
    }

    private func diskAnswer(_ r: DiagnosisReport) -> String {
        let s = r.systemSnapshot
        let usedPct = s.diskTotalGB > 0 ? Int(Double(s.diskTotalGB - s.diskFreeGB) / Double(s.diskTotalGB) * 100) : 0
        var out = ["【ディスクの状況】",
                   "・空き \(s.diskFreeGB)GB / 全体 \(s.diskTotalGB)GB（使用 約\(usedPct)%）"]
        if s.diskFreeGB < 10 {
            out.append("⚠️ 空きが少なめです。10GB を切ると動作不安定や更新失敗の原因になります。")
        }
        out.append(contentsOf: findingsBlock(r, category: .disk))
        out.append("")
        out.append("【リスクなく空ける手順】")
        out.append("1. ストレージタブでスキャン → キャッシュ/ログは安全に削除できます（自動再生成されます）")
        out.append("2. 「ディスク自動ガード」を有効にすると、圧迫時に安全な項目をワンボタン提案、または自動削除＋通知にできます")
        out.append("3. Downloads の古いインストーラー（dmg/pkg）や大容量ファイルは中身を確認のうえ削除")
        return out.joined(separator: "\n")
    }

    private func batteryAnswer(_ r: DiagnosisReport) -> String {
        var out = ["【バッテリー】",
                   "ツールタブのバッテリーで、充放電サイクル数・最大容量（劣化度）・状態を確認できます。"]
        out.append(contentsOf: findingsBlock(r, category: .composite))
        out.append("")
        out.append("【長持ちのコツ】")
        out.append("・最大容量が80%を切ったら劣化が進んでいます。極端な高温/フル充電放置を避けると寿命が延びます。")
        out.append("・高負荷アプリ（CPU上位）を抑えると消費と発熱を減らせます。")
        return out.joined(separator: "\n")
    }

    private func startupAnswer(_ r: DiagnosisReport) -> String {
        var out = ["【起動・ログイン項目】"]
        let block = findingsBlock(r, category: .loginItems)
        if block.isEmpty {
            out.append("目立つ問題は検出されていません。")
        } else {
            out.append(contentsOf: block)
        }
        out.append("")
        out.append("【対処】使っていない自動起動アプリを無効化すると、起動が速くなり常駐メモリも減ります（ログイン項目から管理できます）。")
        return out.joined(separator: "\n")
    }

    private func cpuAnswer(_ r: DiagnosisReport) -> String {
        let s = r.systemSnapshot
        var out = ["【CPU負荷】", "・Load Average: \(s.loadAverage)"]
        if !s.topProcesses.isEmpty {
            out.append("・負荷の高いプロセス: \(s.topProcesses.prefix(3).joined(separator: ", "))")
        }
        out.append(contentsOf: findingsBlock(r, category: .cpu))
        out.append("")
        out.append("【対処】負荷の高いアプリを終了/再起動。バックグラウンドの同期（iCloud/クラウド）やセキュリティスキャンが原因のことも多いです。")
        return out.joined(separator: "\n")
    }

    private func cleanupAnswer(_ r: DiagnosisReport) -> String {
        var out = ["【安全に掃除する】",
                   "リスクなく消せるのは主にキャッシュとログです（アプリが自動再生成するため動作に影響しません）。"]
        out.append("")
        out.append("1. ストレージタブでスキャン → キャッシュ/ログを削除")
        out.append("2. 「ディスク自動ガード」をオンにすると、圧迫時に安全な項目を提案/自動削除（通知のみ）にできます")
        out.append("3. フォント関連キャッシュは表示崩れ防止のため自動で保護・除外されます")
        out.append(contentsOf: findingsBlock(r, category: .disk))
        return out.joined(separator: "\n")
    }

    private func overviewAnswer(_ r: DiagnosisReport) -> String {
        var out = ["【総合診断】総合スコア \(r.overallScore)/100"]
        if r.criticalCount > 0 { out.append("・危険 \(r.criticalCount)件、注意 \(r.warningCount)件") }
        else if r.warningCount > 0 { out.append("・注意 \(r.warningCount)件（危険はなし）") }
        else { out.append("・大きな問題は見つかりませんでした。良好です。") }

        // 重要度の高い上位の指摘と対処
        let top = r.findings
            .filter { $0.severity == .critical || $0.severity == .warning }
            .sorted { $0.severity < $1.severity }
            .prefix(4)
        if !top.isEmpty {
            out.append("")
            out.append("【優先して直すと効果が大きい項目】")
            for f in top {
                out.append("・[\(f.severity.label)] \(f.category.rawValue): \(f.title)")
                out.append("    → \(f.suggestion)")
            }
        }
        out.append("")
        out.append("具体的に知りたい分野（メモリ / ディスク / 起動 / CPU / バッテリー）を聞いてもらえれば、実測値に基づいて詳しくご案内します。")
        return out.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func findingsBlock(_ r: DiagnosisReport, category: DiagnosisCategory) -> [String] {
        let items = r.findings
            .filter { $0.category == category && ($0.severity == .critical || $0.severity == .warning) }
            .sorted { $0.severity < $1.severity }
        guard !items.isEmpty else { return [] }
        var lines = ["", "【検出された指摘】"]
        for f in items.prefix(3) {
            lines.append("・[\(f.severity.label)] \(f.title) — \(f.suggestion)")
        }
        return lines
    }

    private func formatMB(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1fGB", Double(mb) / 1024) : "\(mb)MB"
    }
}
