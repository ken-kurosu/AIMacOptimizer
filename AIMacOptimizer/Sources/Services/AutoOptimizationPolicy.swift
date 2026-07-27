import Foundation

/// Pro自動最適化の発火条件。スケジューラと販売前検証で同じ判定を使う。
enum AutoOptimizationPolicy {
    static func systemAllows(memory: SystemMemoryInfo, usageThreshold: Double) -> Bool {
        MemoryPressurePolicy.shouldAct(memory: memory, usageThreshold: usageThreshold)
    }

    static func profileAllows(_ profile: AppUsageProfile, atHour hour: Int) -> Bool {
        profile.timesOptimized >= 3 && profile.idleConfidence(atHour: hour) > 0.7
    }
}
