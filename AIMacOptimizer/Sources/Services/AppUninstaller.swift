import Foundation
import SwiftUI

// MARK: - Models

struct InstalledApp: Identifiable, Equatable {
    let id: String // bundleIdentifier
    let name: String
    let bundleIdentifier: String
    let appPath: String
    let iconPath: String
    let totalSizeMB: Double
    let appSizeMB: Double
    let leftoverSizeMB: Double
    let leftoverPaths: [String]
    let lastUsed: Date?

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.id == rhs.id
    }
}

struct UninstallResult {
    let removedCount: Int
    let freedMB: Double
    let errors: [String]
}

// MARK: - AppUninstaller

class AppUninstaller: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isScanning: Bool = false

    private let fileManager = FileManager.default

    // MARK: - Public Methods

    /// Scans /Applications for installed apps and their leftover files
    @MainActor
    func scanInstalledApps() async {
        isScanning = true
        defer { isScanning = false }

        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let scannedApps = await self.performScan()
            let sortedApps = scannedApps.sorted { $0.totalSizeMB > $1.totalSizeMB }
            await MainActor.run {
                self.apps = sortedApps
            }
        }.value
    }

    /// Uninstalls an app by moving it and all leftovers to trash
    func uninstallApp(_ app: InstalledApp) -> UninstallResult {
        var removedCount = 0
        var freedMB: Double = 0
        var errors: [String] = []

        // Remove main app（trashItem は同期かつ throwing なので失敗を確実に検知できる）
        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: app.appPath), resultingItemURL: nil)
            removedCount += 1
            freedMB += app.appSizeMB
        } catch {
            errors.append("Failed to recycle app at \(app.appPath): \(error.localizedDescription)")
        }

        // Remove leftover files
        for leftoverPath in app.leftoverPaths {
            let leftoverSize = getDirectorySizeMB(leftoverPath)
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: leftoverPath), resultingItemURL: nil)
                removedCount += 1
                freedMB += leftoverSize
            } catch {
                errors.append("Failed to recycle leftover at \(leftoverPath): \(error.localizedDescription)")
            }
        }

        return UninstallResult(removedCount: removedCount, freedMB: freedMB, errors: errors)
    }

    /// Removes only leftover files associated with an app, keeping the app itself
    func removeLeftoversOnly(_ app: InstalledApp) -> UninstallResult {
        var removedCount = 0
        var freedMB: Double = 0
        var errors: [String] = []

        for leftoverPath in app.leftoverPaths {
            let leftoverSize = getDirectorySizeMB(leftoverPath)
            do {
                try fileManager.trashItem(at: URL(fileURLWithPath: leftoverPath), resultingItemURL: nil)
                removedCount += 1
                freedMB += leftoverSize
            } catch {
                errors.append("Failed to recycle leftover at \(leftoverPath): \(error.localizedDescription)")
            }
        }

        return UninstallResult(removedCount: removedCount, freedMB: freedMB, errors: errors)
    }

    /// Calculates the total size of a directory or file in MB
    func getDirectorySizeMB(_ path: String) -> Double {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

        // ディレクトリは中身を再帰集計する。
        // （attributesOfItem はディレクトリでも例外を投げず、ディレクトリ自体の
        //  数KBの値を返すだけなので、以前はフォルダが常に≒0MBになっていた）
        if isDir.boolValue {
            return calculateDirectorySizeRecursive(path)
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber {
            return Double(size.int64Value) / (1024 * 1024)
        }
        return 0
    }

    // MARK: - Private Methods

    private func performScan() async -> [InstalledApp] {
        let applicationsPath = "/Applications"
        guard fileManager.fileExists(atPath: applicationsPath) else { return [] }

        var scannedApps: [InstalledApp] = []

        do {
            let appNames = try fileManager.contentsOfDirectory(atPath: applicationsPath)
            for appName in appNames {
                let appPath = (applicationsPath as NSString).appendingPathComponent(appName)

                // Skip system apps
                if appPath.hasPrefix("/System/") {
                    continue
                }

                // Only process .app bundles
                guard appName.hasSuffix(".app") else { continue }

                if let installedApp = await loadAppInfo(appPath: appPath, appName: appName) {
                    scannedApps.append(installedApp)
                }
            }
        } catch {
            print("Error scanning /Applications: \(error)")
        }

        return scannedApps
    }

    private func loadAppInfo(appPath: String, appName: String) async -> InstalledApp? {
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")

        guard fileManager.fileExists(atPath: infoPlistPath) else { return nil }

        var bundleIdentifier = ""
        var displayName = appName.replacingOccurrences(of: ".app", with: "")

        if let plist = NSDictionary(contentsOfFile: infoPlistPath) {
            if let identifier = plist["CFBundleIdentifier"] as? String {
                bundleIdentifier = identifier
            }
            if let name = plist["CFBundleDisplayName"] as? String {
                displayName = name
            } else if let name = plist["CFBundleName"] as? String {
                displayName = name
            }
        }

        guard !bundleIdentifier.isEmpty else { return nil }

        let iconPath = getAppIconPath(appPath: appPath)
        let appSizeMB = getDirectorySizeMB(appPath)
        let leftoverPaths = findLeftoverPaths(bundleIdentifier: bundleIdentifier, appName: displayName)
        let leftoverSizeMB = leftoverPaths.reduce(0) { $0 + getDirectorySizeMB($1) }
        let totalSizeMB = appSizeMB + leftoverSizeMB
        let lastUsed = getLastUsedDate(bundleIdentifier: bundleIdentifier)

        return InstalledApp(
            id: bundleIdentifier,
            name: displayName,
            bundleIdentifier: bundleIdentifier,
            appPath: appPath,
            iconPath: iconPath,
            totalSizeMB: totalSizeMB,
            appSizeMB: appSizeMB,
            leftoverSizeMB: leftoverSizeMB,
            leftoverPaths: leftoverPaths,
            lastUsed: lastUsed
        )
    }

    private func getAppIconPath(appPath: String) -> String {
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return ""
        }

        if let iconFile = plist["CFBundleIconFile"] as? String {
            var iconPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
            iconPath = (iconPath as NSString).appendingPathComponent(iconFile)
            if !iconPath.hasSuffix(".icns") {
                iconPath += ".icns"
            }
            if fileManager.fileExists(atPath: iconPath) {
                return iconPath
            }
        }

        return ""
    }

    private func findLeftoverPaths(bundleIdentifier: String, appName: String) -> [String] {
        var leftoverPaths: [String] = []
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let libraryPath = (homeDir as NSString).appendingPathComponent("Library")

        let leftoverLocations: [(String, [String])] = [
            ("Application Support", [bundleIdentifier, appName]),
            ("Caches", [bundleIdentifier]),
            ("Preferences", [bundleIdentifier + ".plist"]),
            ("Logs", [bundleIdentifier, appName]),
            ("Containers", [bundleIdentifier]),
            ("Saved Application State", [bundleIdentifier + ".savedState"]),
            ("HTTPStorages", [bundleIdentifier]),
            ("WebKit", [bundleIdentifier]),
        ]

        for (locationName, searchPatterns) in leftoverLocations {
            let locationPath = (libraryPath as NSString).appendingPathComponent(locationName)
            guard fileManager.fileExists(atPath: locationPath) else { continue }

            for pattern in searchPatterns {
                let itemPath = (locationPath as NSString).appendingPathComponent(pattern)
                if fileManager.fileExists(atPath: itemPath) {
                    leftoverPaths.append(itemPath)
                }
            }
        }

        return leftoverPaths
    }

    private func getLastUsedDate(bundleIdentifier: String) -> Date? {
        // Launch Services データベースの照会が必要なため未実装。現状は nil を返す。
        return nil
    }

    private func calculateDirectorySizeRecursive(_ path: String) -> Double {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(atPath: path) {
            for case let file as String in enumerator {
                let filePath = (path as NSString).appendingPathComponent(file)
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    if let fileSize = attributes[.size] as? NSNumber {
                        totalSize += fileSize.int64Value
                    }
                } catch {
                    continue
                }
            }
        }

        return Double(totalSize) / (1024 * 1024)
    }
}
