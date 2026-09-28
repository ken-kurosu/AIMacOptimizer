import AppKit
import Foundation

// ポップオーバーと同じ分析処理で「AI最適化提案」と「ワンクリック最適化で実際に実行される内容」を表示する。
// 読み取りのみ：何も終了・削除しない。Safari/Chromeのタブは読まない（権限ダイアログと閲覧内容の読み取りを避ける）。

@MainActor
func run() async {
    AppActivityTracker.shared.start()
    let monitor = ProcessMonitor()
    let memory = monitor.sampleMemory()
    let processes = monitor.fetchTopProcessesOnce()

    let suggestions = await SmartAdvisor().analyze(
        systemMemory: memory, processes: processes, chromeTabs: nil, includeBrowserTabs: false
    )

    print(String(format: "メモリ: 使用 %.0f%% ／ 圧迫度 %@", memory.usagePercent, memory.pressureLevel.rawValue))
    print("\n=== AI最適化提案（\(suggestions.count)件）===")
    for (i, s) in suggestions.enumerated() {
        let selected = s.detailItems.filter(\.isSelected).count
        let willRun = s.detailItems.isEmpty || selected > 0
        print("\n[\(i + 1)] \(s.title)  — \(willRun ? "▶ ワンクリックで実行される" : "・実行されない（チェックなし）")")
        print("    種類: \(s.type.rawValue) ／ \(s.description)")
        for d in s.detailItems {
            print("    \(d.isSelected ? "☑" : "☐") \(d.name)（\(d.sizeFormatted)）\(d.isRecommended ? " ★推奨" : "")")
        }
    }

    let vm = PopoverViewModel()
    vm.suggestions = suggestions
    print("\n=== ワンクリック最適化ボタンの表示 ===")
    if let p = vm.optimizePreview {
        print("ボタン: 「ワンクリック最適化（\(p.count)件）」")
        for line in p.lines { print("   ・\(line)") }
        print("   見込み 約\(p.estimatedFormatted)")
        print("注記:   \(p.riskNote)")
    } else {
        print("（実行対象なし）")
    }

    // 件数がチェックに追従するか（未チェックの項目を1つ付ける→+1、外す→元に戻る）
    let before = vm.optimizePreview?.count ?? 0
    if let si = vm.suggestions.firstIndex(where: { $0.detailItems.contains { !$0.isSelected } }),
       let di = vm.suggestions[si].detailItems.firstIndex(where: { !$0.isSelected }) {
        vm.suggestions[si].detailItems[di].isSelected = true
        let checked = vm.optimizePreview?.count ?? 0
        vm.suggestions[si].detailItems[di].isSelected = false
        let restored = vm.optimizePreview?.count ?? 0
        print("\n=== 件数の追従チェック（\(vm.suggestions[si].detailItems[di].name) を付け外し）===")
        print("\(before)件 → チェック \(checked)件 → 外す \(restored)件")
        precondition(checked == before + 1 && restored == before, "件数がチェックに追従していない")
        print("PASS: 件数はチェックの数どおりに増減する")
    }
}

await run()
