import Foundation

/// Represents system storage information
struct StorageInfo {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double

    var usagePercent: Double {
        guard totalGB > 0 else { return 0 }
        return (usedGB / totalGB) * 100
    }

    var freeFormatted: String { formatSize(freeGB * 1024) }
    var usedFormatted: String { formatSize(usedGB * 1024) }
    var totalFormatted: String { formatSize(totalGB * 1024) }

    private func formatSize(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

/// A large file or folder found during storage analysis
struct StorageItem: Identifiable, Comparable {
    let id = UUID()
    let path: String
    let name: String
    let sizeMB: Double
    let category: StorageCategory
    let isDirectory: Bool
    /// Individual files inside this directory (populated on expand)
    var subItems: [StorageSubItem] = []

    var sizeFormatted: String {
        if sizeMB >= 1024 {
            return String(format: "%.1f GB", sizeMB / 1024)
        }
        return String(format: "%.0f MB", sizeMB)
    }

    static func < (lhs: StorageItem, rhs: StorageItem) -> Bool {
        lhs.sizeMB < rhs.sizeMB
    }

    static func == (lhs: StorageItem, rhs: StorageItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Individual file within a storage directory
struct StorageSubItem: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let sizeMB: Double
    var isSelected: Bool = true
    var isRecommended: Bool = false
    var reason: String = ""

    var sizeFormatted: String {
        if sizeMB >= 1024 {
            return String(format: "%.1f GB", sizeMB / 1024)
        }
        return String(format: "%.0f MB", sizeMB)
    }
}

/// Category for storage items
enum StorageCategory: String, CaseIterable {
    case cache = "キャッシュ"
    case log = "ログ"
    case installer = "インストーラー"
    case largeFile = "大容量ファイル"
    case downloadedFile = "ダウンロード"
    case icloudCandidate = "iCloud退避候補"

    var icon: String {
        switch self {
        case .cache: return "folder.badge.gearshape"
        case .log: return "doc.text"
        case .installer: return "arrow.down.circle"
        case .largeFile: return "doc.zipper"
        case .downloadedFile: return "arrow.down.doc"
        case .icloudCandidate: return "icloud.and.arrow.up"
        }
    }

    /// Whether this category requires user confirmation before deletion
    var requiresConfirmation: Bool {
        switch self {
        case .cache, .log: return false // Safe to delete
        case .installer, .largeFile, .downloadedFile, .icloudCandidate: return true
        }
    }

    /// Localized display name (rawValue kept stable for persistence/comparison)
    var localizedName: String {
        switch self {
        case .cache: return L10n.storageCacheName
        case .log: return L10n.storageLogName
        case .installer: return L10n.storageInstallerName
        case .largeFile: return L10n.storageLargeFileName
        case .downloadedFile: return L10n.storageDownloadName
        case .icloudCandidate: return L10n.storageICloudCandidateName
        }
    }
}

/// Action that can be taken on a storage item
enum StorageAction: String {
    case delete = "削除"
    case moveToTrash = "ゴミ箱に移動"
    case moveToICloud = "iCloudに退避"

    /// Localized display name (rawValue kept stable for comparison)
    var localizedName: String {
        switch self {
        case .delete: return L10n.storageActionDelete
        case .moveToTrash: return L10n.storageActionMoveToTrash
        case .moveToICloud: return L10n.storageActionMoveToICloud
        }
    }
}

/// Result of a storage cleanup operation
struct StorageCleanupResult {
    var freedMB: Double = 0
    var deletedItems: Int = 0
    var movedToICloud: Int = 0
    var errors: [String] = []
}
