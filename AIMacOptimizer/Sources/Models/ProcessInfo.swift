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

    var usagePercent: Double {
        guard totalMB > 0 else { return 0 }
        return (usedMB / totalMB) * 100
    }

    var freePercent: Double {
        guard totalMB > 0 else { return 100 }
        return (freeMB / totalMB) * 100
    }

    var severity: MemorySeverity {
        if freePercent > 40 { return .low }
        if freePercent > 20 { return .medium }
        return .high
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
}
