import Foundation

/// 診断の「全て修復」で一括操作してはいけない対象を一元管理する。
enum DiagnosisBulkRepairPolicy {
    static func requiresManualHandling(path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path
            .contains("/Library/Developer/CoreSimulator")
    }
}
