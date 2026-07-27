import Foundation

/// Represents a running process with its memory usage
struct ProcessMemoryInfo: Identifiable, Comparable {
    let id: pid_t
    let name: String
    let memoryMB: Double
    let isSystemProcess: Bool
    let bundleIdentifier: String?

    var memoryFormatted: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.0f MB", memoryMB)
    }

    static func < (lhs: ProcessMemoryInfo, rhs: ProcessMemoryInfo) -> Bool {
        lhs.memoryMB < rhs.memoryMB
    }
}

/// System-wide memory statistics
struct SystemMemoryInfo {
    let totalMB: Double
    let usedMB: Double
    let freeMB: Double
    let compressedMB: Double
    let swapUsedMB: Double
    /// vm_statistics64 の回収可能ページと直近のswap入出力から算出した圧迫度。
    let pressureLevel: MemoryPressureLevel
    let swapInsMBPerSecond: Double
    let swapOutsMBPerSecond: Double

    init(totalMB: Double, usedMB: Double, freeMB: Double, compressedMB: Double,
         swapUsedMB: Double, pressureLevel: MemoryPressureLevel = .green,
         swapInsMBPerSecond: Double = 0, swapOutsMBPerSecond: Double = 0) {
        self.totalMB = totalMB
        self.usedMB = usedMB
        self.freeMB = freeMB
        self.compressedMB = compressedMB
        self.swapUsedMB = swapUsedMB
        self.pressureLevel = pressureLevel
        self.swapInsMBPerSecond = swapInsMBPerSecond
        self.swapOutsMBPerSecond = swapOutsMBPerSecond
    }

    var usagePercent: Double {
        guard totalMB > 0 else { return 0 }
        return (usedMB / totalMB) * 100
    }

    var freePercent: Double {
        guard totalMB > 0 else { return 100 }
        return (freeMB / totalMB) * 100
    }

    var severity: MemorySeverity {
        switch pressureLevel {
        case .green: return .low
        case .yellow: return .medium
        case .red: return .high
        }
    }

    var hasRecentSwapActivity: Bool {
        swapInsMBPerSecond > 0.01 || swapOutsMBPerSecond > 0.01
    }

    var totalFormatted: String { formatMemory(totalMB) }
    var usedFormatted: String { formatMemory(usedMB) }
    var freeFormatted: String { formatMemory(freeMB) }
    var swapFormatted: String { formatMemory(swapUsedMB) }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

enum MemoryPressureLevel: String, Codable {
    case green
    case yellow
    case red
}

enum MemorySeverity: String {
    case low = "良好"
    case medium = "注意"
    case high = "逼迫"

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "red"
        }
    }

    /// Localized display name (rawValue is kept stable for persistence/comparison)
    var localizedName: String {
        switch self {
        case .low: return L10n.severityLow
        case .medium: return L10n.severityMedium
        case .high: return L10n.severityHigh
        }
    }
}
