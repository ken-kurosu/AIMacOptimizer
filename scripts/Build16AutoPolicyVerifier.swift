import Foundation

@main
struct Build16AutoPolicyVerifier {
    static func main() {
        let currentHour = 14
        var profile = AppUsageProfile(
            appName: "FixtureApp",
            activeHours: [9],
            averageMemoryMB: 600,
            timesOptimized: 0,
            timesIgnored: 0,
            lastSeen: Date()
        )

        profile.timesOptimized = 2
        precondition(!AutoOptimizationPolicy.profileAllows(profile, atHour: currentHour))
        profile.timesOptimized = 3
        precondition(AutoOptimizationPolicy.profileAllows(profile, atHour: currentHour))
        precondition(!AutoOptimizationPolicy.profileAllows(profile, atHour: 9))

        let green = memory(usagePercent: 95, pressure: .green, swapOut: 0.2)
        precondition(!AutoOptimizationPolicy.systemAllows(memory: green, usageThreshold: 90))

        let belowThreshold = memory(usagePercent: 85, pressure: .yellow, swapOut: 0.2)
        precondition(!AutoOptimizationPolicy.systemAllows(memory: belowThreshold, usageThreshold: 90))

        let eligible = memory(usagePercent: 95, pressure: .yellow, swapOut: 0.2)
        precondition(AutoOptimizationPolicy.systemAllows(memory: eligible, usageThreshold: 90))

        print("PASS: 手動最適化3回後、しきい値・圧迫・アイドル条件を満たす場合だけ自動化可能")
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
