import Foundation

@main
struct Build16MemoryPolicyVerifier {
    static func main() {
        let greenHighUsage = memory(usagePercent: 95, pressure: .green, swapOut: 0.5)
        precondition(!MemoryPressurePolicy.shouldAct(memory: greenHighUsage, usageThreshold: 80))

        let yellowNoSwap = memory(usagePercent: 95, pressure: .yellow, swapOut: 0)
        precondition(!MemoryPressurePolicy.shouldAct(memory: yellowNoSwap, usageThreshold: 80))

        let yellowWithSwap = memory(usagePercent: 95, pressure: .yellow, swapOut: 0.02)
        precondition(MemoryPressurePolicy.shouldAct(memory: yellowWithSwap, usageThreshold: 80))

        let redWithSwap = memory(usagePercent: 95, pressure: .red, swapOut: 0.2)
        precondition(MemoryPressurePolicy.shouldAct(memory: redWithSwap, usageThreshold: 80))

        precondition(MemoryPressurePolicy.classify(
            reclaimableRatio: 0.2, compressedRatio: 0.4,
            swapInsMBPerSecond: 0, swapOutsMBPerSecond: 0
        ) == .green)
        precondition(MemoryPressurePolicy.classify(
            reclaimableRatio: 0.1, compressedRatio: 0.1,
            swapInsMBPerSecond: 0.02, swapOutsMBPerSecond: 0
        ) == .yellow)
        precondition(MemoryPressurePolicy.classify(
            reclaimableRatio: 0.03, compressedRatio: 0.1,
            swapInsMBPerSecond: 0, swapOutsMBPerSecond: 0.2
        ) == .red)

        print("PASS: 緑の高使用率では発火せず、黄/赤かつSwap発生時だけ発火")
    }

    private static func memory(
        usagePercent: Double,
        pressure: MemoryPressureLevel,
        swapOut: Double
    ) -> SystemMemoryInfo {
        let total = 1_000.0
        return SystemMemoryInfo(
            totalMB: total,
            usedMB: total * usagePercent / 100,
            freeMB: total * (100 - usagePercent) / 100,
            compressedMB: 0,
            swapUsedMB: 100,
            pressureLevel: pressure,
            swapInsMBPerSecond: 0,
            swapOutsMBPerSecond: swapOut
        )
    }
}
