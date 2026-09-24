import AppKit
import Foundation

// 「メモリ使用量の多いアプリ」終了候補が、このMacで実際に何を出すかを試走する。
// UIは開かない・何も終了しない（読み取りのみ）。
// 注: 起動直後相当のため「直近10分アクティブ」の記録は最前面アプリだけ。

AppActivityTracker.shared.start()
let snapshot = ProcessMonitor().fetchOnce()
let candidates = SmartAdvisor().findTopMemoryApps(snapshot.processes)

let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
print("最前面(除外): \(front)")
print("候補 \(candidates.count) 件（RSS≥200MB・上位5件）:")
for c in candidates {
    print(String(format: "  %-32@ %7.0f MB  %@", c.name as NSString, c.memoryMB, (c.bundleIdentifier ?? "-") as NSString))
}

// 安全性の不変条件
let selfBundle = Bundle.main.bundleIdentifier
precondition(candidates.count <= 5, "候補は最大5件")
precondition(candidates.allSatisfy { $0.memoryMB >= 200 }, "200MB未満が混入")
precondition(candidates.allSatisfy { !$0.isSystemProcess }, "システムプロセスが混入")
precondition(!candidates.contains { $0.bundleIdentifier != nil && $0.bundleIdentifier == NSWorkspace.shared.frontmostApplication?.bundleIdentifier }, "最前面アプリが混入")
precondition(!candidates.contains { $0.bundleIdentifier != nil && $0.bundleIdentifier == selfBundle }, "自分自身が混入")
precondition(zip(candidates, candidates.dropFirst()).allSatisfy { $0.memoryMB >= $1.memoryMB }, "RSS降順でない")
print("PASS: 件数・しきい値・除外・並び順の不変条件を満たす")
