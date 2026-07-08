import Foundation
import AppKit

/// Analyzes disk storage and finds large/unnecessary files
final class StorageAnalyzer: ObservableObject {
    @Published var storageInfo = StorageInfo(totalGB: 0, usedGB: 0, freeGB: 0)
    @Published var items: [StorageItem] = []
    @Published var isScanning = false

    private let fileManager = FileManager.default

    // MARK: - Storage Overview

    /// Get current disk storage statistics
    func getStorageInfo() -> StorageInfo {
        guard let attrs = try? fileManager.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else {
            return StorageInfo(totalGB: 0, usedGB: 0, freeGB: 0)
        }

        let totalBytes = (attrs[.systemSize] as? Int64) ?? 0
        let freeBytes = (attrs[.systemFreeSize] as? Int64) ?? 0
        let usedBytes = totalBytes - freeBytes

        // macOS 10.6 以降の Finder / About This Mac / システム設定は 10進(1000基準, GB) でディスク容量を表示する。
        // ここを 1024基準(GiB) にすると約7.4%小さく出て「値が違う」と見える。Finder に合わせて 10進にする。
        // （RAM は 2進が正なので MemoryOptimizer/ProcessMonitor 側は 1024 のまま）
        return StorageInfo(
            totalGB: Double(totalBytes) / 1000 / 1000 / 1000,
            usedGB: Double(usedBytes) / 1000 / 1000 / 1000,
            freeGB: Double(freeBytes) / 1000 / 1000 / 1000
        )
    }

    // MARK: - Full Scan

    /// Scan for caches, logs, installers, and large files
    func scan() async {
        await MainActor.run { isScanning = true }

        let caches = scanCaches()
        let logs = scanLogs()
        let installers = scanInstallers()
        let largeFiles = scanLargeFiles()
        let devBig = scanDeveloperBigConsumers()

        var results: [StorageItem] = []
        results.append(contentsOf: caches)
        results.append(contentsOf: logs)
        results.append(contentsOf: installers)
        results.append(contentsOf: largeFiles)
        results.append(contentsOf: devBig)
        results.sort(by: >)
        let finalResults = results  // 並行クロージャに渡すため不変コピーを作る（Swift 6対応）

        await MainActor.run {
            self.storageInfo = getStorageInfo()
            self.items = finalResults
            self.isScanning = false
        }
    }

    /// 圧迫回避向けに「安全に削除できる」キャッシュ/ログのみを返す。
    /// フォント等の保護対象は除外済みなので、そのまま提案・自動削除に使える。
    func findSafeCleanupItems() -> [StorageItem] {
        let items = scanCaches() + scanLogs()
        return items
            .filter { !isProtectedPath($0.name) && !isProtectedPath($0.path) }
            .sorted(by: >)
    }

    // MARK: - Cache Scanning

    private func scanCaches() -> [StorageItem] {
        var results: [StorageItem] = []
        let home = NSHomeDirectory()

        // 再生成される安全な大型キャッシュ。実機の整理で「キャッシュ本体(~/Library/Caches)より
        // これらの方が大きく空く」ことが多いため対象に含める（Xcode/Adobe/Cursor 等）。
        let cachePaths = [
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support/Google/Chrome/Default/Cache",
            "\(home)/Library/Application Support/Google/Chrome/Default/Code Cache",
            "\(home)/Library/Application Support/Slack/Cache",
            "\(home)/Library/Application Support/discord/Cache",
            // Xcode ビルド中間物（次回ビルドで再生成）
            "\(home)/Library/Developer/Xcode/DerivedData",
            // Adobe のメディアキャッシュ（再生成される。元の動画/画像は無事）
            "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
            "\(home)/Library/Application Support/Adobe/Common/Peak Files",
            // Cursor / VS Code 系の再生成キャッシュ
            "\(home)/Library/Application Support/Cursor/Cache",
            "\(home)/Library/Application Support/Cursor/CachedData",
            "\(home)/Library/Application Support/Cursor/Code Cache",
            "\(home)/Library/Application Support/Code/Cache",
            "\(home)/Library/Application Support/Code/CachedData",
        ]

        for path in cachePaths {
            if let size = directorySize(path), size > 50 { // >50MB
                let name = (path as NSString).lastPathComponent
                let parentApp = extractAppName(from: path)
                results.append(StorageItem(
                    path: path,
                    name: "\(parentApp) - \(name)",
                    sizeMB: size,
                    category: .cache,
                    isDirectory: true
                ))
            }
        }

        return results
    }

    // MARK: - Log Scanning

    private func scanLogs() -> [StorageItem] {
        var results: [StorageItem] = []
        let home = NSHomeDirectory()

        // /private/var/log はシステム管理・root所有・syslogd等が使用中のため対象外
        //（/var/folders と同類。ユーザー領域の ~/Library/Logs のみ扱う）
        let logPaths = [
            "\(home)/Library/Logs",
        ]

        for path in logPaths {
            if let size = directorySize(path), size > 50 {
                let name = (path as NSString).lastPathComponent
                results.append(StorageItem(
                    path: path,
                    name: name,
                    sizeMB: size,
                    category: .log,
                    isDirectory: true
                ))
            }
        }

        return results
    }

    // MARK: - Installer Scanning (DMG, PKG)

    private func scanInstallers() -> [StorageItem] {
        var results: [StorageItem] = []
        let downloads = "\(NSHomeDirectory())/Downloads"

        guard let contents = try? fileManager.contentsOfDirectory(atPath: downloads) else {
            return []
        }

        let installerExtensions = ["dmg", "pkg", "iso"]

        for item in contents {
            let ext = (item as NSString).pathExtension.lowercased()
            guard installerExtensions.contains(ext) else { continue }

            let fullPath = "\(downloads)/\(item)"
            if let size = fileSize(fullPath), size > 10 { // >10MB
                results.append(StorageItem(
                    path: fullPath,
                    name: item,
                    sizeMB: size,
                    category: .installer,
                    isDirectory: false
                ))
            }
        }

        return results
    }

    // MARK: - Large File Detection

    private func scanLargeFiles() -> [StorageItem] {
        var results: [StorageItem] = []
        let home = NSHomeDirectory()

        let searchPaths = [
            "\(home)/Downloads",
            "\(home)/Documents",
        ]

        for searchPath in searchPaths {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: searchPath) else {
                continue
            }

            for item in contents {
                let fullPath = "\(searchPath)/\(item)"
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)

                let size: Double?
                if isDir.boolValue {
                    size = directorySize(fullPath)
                } else {
                    size = fileSize(fullPath)
                }

                if let size = size, size > 500 { // >500MB
                    // Skip installers (already captured)
                    let ext = (item as NSString).pathExtension.lowercased()
                    if ["dmg", "pkg", "iso"].contains(ext) { continue }

                    results.append(StorageItem(
                        path: fullPath,
                        name: item,
                        sizeMB: size,
                        category: .largeFile,
                        isDirectory: isDir.boolValue
                    ))
                }
            }
        }

        return results
    }

    /// 開発系の「隠れた大物」を検出する（Ollama モデル / iOS シミュレータ / Docker）。
    /// Finder では見つけにくいが数GB〜数十GBを占めることが多い。再生成キャッシュではなく
    /// 意図的なデータのため .largeFile として扱い、自動削除(findSafeCleanupItems)には含めない。
    /// 削除は必ず個別確認・ゴミ箱経由（＝ユーザーが理解・同意した上でだけ）。
    private func scanDeveloperBigConsumers() -> [StorageItem] {
        var results: [StorageItem] = []
        let home = NSHomeDirectory()

        let candidates: [(path: String, label: String)] = [
            ("\(home)/.ollama/models", "Ollama モデル"),
            ("\(home)/Library/Developer/CoreSimulator/Devices", "iOS シミュレータ"),
            ("\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "Docker ディスクイメージ"),
            ("\(home)/Library/Containers/com.docker.docker/Data", "Docker データ"),
        ]

        var dockerCounted = false
        for c in candidates {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: c.path, isDirectory: &isDir) else { continue }
            // Docker は Docker.raw を優先し、データディレクトリとの二重計上を避ける
            if c.label.hasPrefix("Docker") {
                if dockerCounted { continue }
            }
            let size = isDir.boolValue ? directorySize(c.path) : fileSize(c.path)
            guard let size = size, size > 500 else { continue } // >500MB のみ提示
            if c.label.hasPrefix("Docker") { dockerCounted = true }
            results.append(StorageItem(
                path: c.path,
                name: c.label,
                sizeMB: size,
                category: .largeFile,
                isDirectory: isDir.boolValue
            ))
        }
        return results
    }

    // MARK: - Cleanup Actions (Require Confirmation)

    /// Paths that must NEVER be deleted (font caches, system-critical data)
    private static let protectedPaths: Set<String> = [
        "com.apple.FontRegistry",
        "com.apple.fontvaliator",
        "com.apple.ATS",
        "FontRegistry",
        "com.apple.font",
    ]

    /// Check if a path is protected from deletion
    private func isProtectedPath(_ name: String) -> Bool {
        for protected in Self.protectedPaths {
            if name.lowercased().contains(protected.lowercased()) { return true }
        }
        // Also protect anything with "font" in the name
        if name.lowercased().contains("font") { return true }
        return false
    }

    /// Delete a cache or log directory (safe, no confirmation needed)
    /// ⚠️ Skips font-related caches to prevent browser font rendering issues
    /// システム管理領域（削除してはいけない）かどうか
    private func isSystemPath(_ path: String) -> Bool {
        let denylist = ["/system", "/private/var/log", "/private/var/folders", "/var/folders", "/var/log", "/library/"]
        let l = path.lowercased()
        // ルート直下の /Library（ユーザーの ~/Library ではない）も保護
        if l == "/library" || l.hasPrefix("/library/") { return true }
        return denylist.contains { l.hasPrefix($0) }
    }

    /// キャッシュ/ログの安全削除。実際に削除できた時だけ true を返す（失敗時に空解放を報告しない）。
    func clearCache(_ item: StorageItem) -> Bool {
        guard item.category == .cache || item.category == .log else { return false }

        // フォント関連・システム領域は削除しない
        if isProtectedPath(item.name) || isProtectedPath(item.path) {
            print("⚠️ Skipping protected path: \(item.path)")
            return false
        }
        if isSystemPath(item.path) {
            print("⚠️ Skipping system path: \(item.path)")
            return false
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: item.path) else {
            return false
        }
        var deleted = 0
        for file in contents {
            if isProtectedPath(file) { continue }
            do {
                try fileManager.removeItem(atPath: "\(item.path)/\(file)")
                deleted += 1
            } catch {
                // 個別の失敗は無視するが、成功カウントには含めない
            }
        }
        return deleted > 0
    }

    /// キャッシュを削除し、実際に減った容量(MB)を返す。
    /// （スキャン時の満額ではなく実測差分。保護/ロックでスキップした分を「確保」に含めないため）
    func clearCacheMeasuringFreed(_ item: StorageItem) -> Double {
        let before = directorySize(item.path) ?? item.sizeMB
        guard clearCache(item) else { return 0 }
        let after = directorySize(item.path) ?? 0
        return max(0, before - after)
    }

    /// Move an item to Trash (requires user confirmation)
    func moveToTrash(_ item: StorageItem) -> Bool {
        do {
            var resultURL: NSURL?
            try fileManager.trashItem(
                at: URL(fileURLWithPath: item.path),
                resultingItemURL: &resultURL
            )
            return true
        } catch {
            print("Failed to trash \(item.name): \(error)")
            return false
        }
    }

    /// Move selected sub-items to Trash (only deletes chosen files)
    func moveSubItemsToTrash(_ subItems: [StorageSubItem]) -> (success: Int, failed: Int) {
        var success = 0
        var failed = 0
        for subItem in subItems {
            do {
                var resultURL: NSURL?
                try fileManager.trashItem(
                    at: URL(fileURLWithPath: subItem.path),
                    resultingItemURL: &resultURL
                )
                success += 1
            } catch {
                print("Failed to trash \(subItem.name): \(error)")
                failed += 1
            }
        }
        return (success, failed)
    }

    /// Move an item to iCloud Drive (requires user confirmation)
    func moveToICloud(_ item: StorageItem) -> Bool {
        let icloudBase = "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs"
        let backupDir = "\(icloudBase)/AIMacOptimizer_Backup"

        // Create backup directory if needed
        try? fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

        let dest = "\(backupDir)/\(item.name)"
        do {
            try fileManager.moveItem(atPath: item.path, toPath: dest)
            return true
        } catch {
            print("Failed to move to iCloud: \(error)")
            return false
        }
    }

    /// Move selected sub-items to iCloud Drive (only moves chosen files)
    func moveSubItemsToICloud(_ subItems: [StorageSubItem]) -> (success: Int, failed: Int) {
        let icloudBase = "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs"
        let backupDir = "\(icloudBase)/AIMacOptimizer_Backup"
        try? fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

        var success = 0
        var failed = 0
        for subItem in subItems {
            let dest = "\(backupDir)/\(subItem.name)"
            do {
                try fileManager.moveItem(atPath: subItem.path, toPath: dest)
                success += 1
            } catch {
                print("Failed to move \(subItem.name) to iCloud: \(error)")
                failed += 1
            }
        }
        return (success, failed)
    }

    /// Clear only selected sub-items within a cache/log directory
    /// ⚠️ Skips font-related files to prevent browser font rendering issues
    func clearSelectedSubItems(_ subItems: [StorageSubItem]) -> (success: Int, failed: Int) {
        var success = 0
        var failed = 0
        for subItem in subItems {
            // フォント関連・システム領域は削除しない
            if isProtectedPath(subItem.name) || isProtectedPath(subItem.path) || isSystemPath(subItem.path) {
                print("⚠️ Skipping protected sub-item: \(subItem.path)")
                failed += 1
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subItem.path, isDirectory: &isDir) else { failed += 1; continue }

            if isDir.boolValue {
                // ディレクトリ自体は削除せず、中身だけを1件ずつ保護付きで削除する。
                // （未展開のカテゴリ丸ごと ~/Library/Caches 等を渡された時に、
                //  フォントキャッシュ(com.apple.FontRegistry 等)まで巻き込んで消す事故を防ぐ）
                guard let contents = try? fileManager.contentsOfDirectory(atPath: subItem.path) else { failed += 1; continue }
                var cleared = false
                for entry in contents {
                    if isProtectedPath(entry) { continue }   // フォント等はスキップ
                    if (try? fileManager.removeItem(atPath: "\(subItem.path)/\(entry)")) != nil { cleared = true }
                }
                if cleared { success += 1 } else { failed += 1 }
            } else {
                do {
                    try fileManager.removeItem(atPath: subItem.path)
                    success += 1
                } catch {
                    print("Failed to delete \(subItem.name): \(error)")
                    failed += 1
                }
            }
        }
        return (success, failed)
    }

    // MARK: - Sub-Item Scanning

    /// Get individual files inside a storage directory for detailed view
    func getSubItems(for item: StorageItem) -> [StorageSubItem] {
        guard item.isDirectory else {
            return [StorageSubItem(
                path: item.path, name: item.name, sizeMB: item.sizeMB,
                isSelected: true, isRecommended: true,
                reason: classifyFileReason(name: item.name, category: item.category)
            )]
        }

        var subItems: [StorageSubItem] = []
        guard let contents = try? fileManager.contentsOfDirectory(atPath: item.path) else {
            return []
        }

        for fileName in contents {
            let fullPath = "\(item.path)/\(fileName)"
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)

            let size: Double?
            if isDir.boolValue {
                size = directorySize(fullPath)
            } else {
                size = fileSize(fullPath)
            }

            guard let fileSizeMB = size, fileSizeMB > 1 else { continue }

            let reason = classifyFileReason(name: fileName, category: item.category)
            let recommended = isRecommendedForDeletion(name: fileName, category: item.category, sizeMB: fileSizeMB)

            subItems.append(StorageSubItem(
                path: fullPath, name: fileName, sizeMB: fileSizeMB,
                isSelected: recommended, isRecommended: recommended, reason: reason
            ))
        }

        return Array(subItems.sorted { $0.sizeMB > $1.sizeMB }.prefix(20))
    }

    private func classifyFileReason(name: String, category: StorageCategory) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch category {
        case .cache:
            if name.contains("GPUCache") { return "GPUキャッシュ — 再生成されるため削除推奨" }
            if name.contains("Code Cache") { return "コードキャッシュ — 再生成されるため削除推奨" }
            if name.contains("blob_storage") { return "Blobストレージ — 一時データ、削除推奨" }
            return "キャッシュデータ — 再生成可能"
        case .log:
            if name.contains("DiagnosticReports") { return "診断レポート — 古いものは削除推奨" }
            if name.contains("CrashReporter") { return "クラッシュレポート — 確認済みなら削除推奨" }
            return "ログデータ — 古いものは削除可能"
        case .installer:
            if ext == "dmg" { return "ディスクイメージ — インストール済みなら不要" }
            if ext == "pkg" { return "インストーラー — インストール済みなら不要" }
            return "インストーラー — 使用済みなら削除推奨"
        case .largeFile:
            if ["zip", "tar", "gz"].contains(ext) { return "圧縮ファイル — 展開済みなら不要" }
            if ["mp4", "mov"].contains(ext) { return "動画ファイル — 容量大" }
            return "大容量ファイル — 必要性を確認"
        case .downloadedFile: return "ダウンロードファイル — 必要性を確認"
        case .icloudCandidate: return "iCloud退避候補 — クラウドに移動して容量節約"
        }
    }

    private func isRecommendedForDeletion(name: String, category: StorageCategory, sizeMB: Double) -> Bool {
        switch category {
        case .cache, .log: return true
        case .installer: return true
        case .largeFile:
            let ext = (name as NSString).pathExtension.lowercased()
            return ["zip", "tar", "gz", "dmg", "pkg", "iso"].contains(ext) || sizeMB > 1000
        case .downloadedFile: return sizeMB > 500
        case .icloudCandidate: return sizeMB > 1000
        }
    }

    // MARK: - Helpers

    private func fileSize(_ path: String) -> Double? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        let bytes = (attrs[.size] as? Int64) ?? 0
        return Double(bytes) / 1024 / 1024
    }

    private func directorySize(_ path: String) -> Double? {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return nil }
        var totalBytes: Int64 = 0

        while let file = enumerator.nextObject() as? String {
            let fullPath = "\(path)/\(file)"
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                totalBytes += (attrs[.size] as? Int64) ?? 0
            }
        }

        let mb = Double(totalBytes) / 1024 / 1024
        return mb > 0 ? mb : nil
    }

    private func extractAppName(from path: String) -> String {
        if path.contains("Chrome") { return "Chrome" }
        if path.contains("Slack") { return "Slack" }
        if path.contains("discord") { return "Discord" }
        if path.contains("Spotify") { return "Spotify" }
        return "システム"
    }
}
