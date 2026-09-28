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
        print("予告: このボタンで実行する内容（\(p.count)件）")
        for line in p.lines { print("   ・\(line)") }
        print("   見込み 約\(p.estimatedFormatted)")
        print("注記:   \(p.riskNote)")
    } else {
        print("（実行対象なし）")
    }
}

await run()
