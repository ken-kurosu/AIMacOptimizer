import Foundation

/// メモリ診断・通知・自動化が共有する、実測ベースの発火ポリシー。
enum MemoryPressurePolicy {
    static func classify(
        reclaimableRatio: Double,
        compressedRatio: Double,
        swapInsMBPerSecond: Double,
        swapOutsMBPerSecond: Double
    ) -> MemoryPressureLevel {
        let pagingActive = swapInsMBPerSecond > 0.01 || swapOutsMBPerSecond > 0.01
        if pagingActive && reclaimableRatio < 0.04 && swapOutsMBPerSecond > 0.10 {
            return .red
        }
        if pagingActive && (reclaimableRatio < 0.12 || compressedRatio > 0.25) {
            return .yellow
        }
        return .green
    }

    /// 高使用率だけでは発火させない。しきい値、黄/赤、直近Swapの全条件を必須にする。
    static func shouldAct(memory: SystemMemoryInfo, usageThreshold: Double) -> Bool {
        memory.usagePercent >= usageThreshold
            && memory.pressureLevel != .green
            && memory.hasRecentSwapActivity
    }
}
