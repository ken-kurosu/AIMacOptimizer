import Foundation
import AppKit

/// Executes memory optimization actions
final class MemoryOptimizer {

    private let fileManager = FileManager.default

    /// Results of an optimization run
    struct OptimizationResult {
        let freedMB: Double
        let closedTabs: Int
        let quitApps: [String]
        let purged: Bool
    }

    // MARK: - RAM Purge

    /// Execute `purge` command to free inactive memory
    func purgeRAM() async -> Bool {
        await runShellCommand("/usr/sbin/purge", arguments: [])
    }

    // MARK: - App Management

    /// Quit a running application by name
    func quitApp(name: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: { $0.localizedName == name }) else {
            return false
        }
        return app.terminate()
    }

    /// Force quit a running application by PID
    func forceQuitApp(pid: pid_t) -> Bool {
        kill(pid, SIGTERM) == 0
    }

    /// Restart an application (quit then relaunch)
    func restartApp(name: String, bundleIdentifier: String?) async -> Bool {
        guard quitApp(name: name) else { return false }

        // Wait for the app to fully quit
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Relaunch
        if let bundleID = bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            do {
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
                return true
            } catch {
                print("Failed to relaunch \(bundleID): \(error)")
                return false
            }
        } else {
            // Fallback: try to open by name
            return await runShellCommand("/usr/bin/open", arguments: ["-a", name])
        }
    }

    // MARK: - DNS Cache Flush

    /// Flush macOS DNS cache to free memory used by name resolution caching
    func flushDNSCache() async -> Bool {
        await runShellCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"])
    }

    // MARK: - Font Cache Clear

    /// Font cache safety level
    enum FontCacheSafety {
        case safe      // Only flush ATS server cache (no file deletion)
        case moderate  // Flush + remove user font cache only
        case aggressive // Full removal including system font DB (DANGEROUS)
    }

    /// Clear font caches safely
    /// ⚠️ IMPORTANT: atsutil databases -remove can break web browser font rendering.
    /// Default is .safe which only flushes the in-memory cache without deleting files.
    func clearFontCache(level: FontCacheSafety = .safe) async -> Bool {
        switch level {
        case .safe:
            // Only flush the ATS font server's in-memory cache
            // This frees some memory without deleting any font database files
            // Fonts will reload normally — no risk of breaking browsers
            return await runShellCommand("/usr/bin/atsutil", arguments: ["server", "-shutdown"])
            // macOS will auto-restart the ATS server

        case .moderate:
            // Flush server + remove ONLY the user-level font cache (not system DB)
            _ = await runShellCommand("/usr/bin/atsutil", arguments: ["server", "-shutdown"])
            let userFontCache = "\(NSHomeDirectory())/Library/Caches/com.apple.FontRegistry"
            if fileManager.fileExists(atPath: userFontCache) {
                try? fileManager.removeItem(atPath: userFontCache)
            }
            return true

        case .aggressive:
            // ⚠️ DANGEROUS: Removes the font database entirely
            // This can cause browsers to fail loading web fonts
            // Requires logout/restart to fully rebuild
            // NOT recommended for automated use
            let result = await runShellCommand("/usr/bin/atsutil", arguments: ["databases", "-remove"])
            return result
        }
    }

    /// Get font cache size (for display purposes only)
    func getFontCacheSizeMB() -> Double {
        let home = NSHomeDirectory()
        return getDirectorySizeMB("\(home)/Library/Caches/com.apple.FontRegistry")
    }

    // MARK: - Temporary Files Cleanup

    /// Get list of temporary file directories and their sizes
    func getTempFileInfo() -> [(path: String, name: String, sizeMB: Double, description: String)] {
        var items: [(path: String, name: String, sizeMB: Double, description: String)] = []
        let home = NSHomeDirectory()

        // 安全に削除できる、明確に一時的なものだけを対象にする。
        // ・/var/folders は除外: macOS 管理の作業領域で稼働中アプリが使用中。OSが自動整理する
        // ・キャッシュ/ログは「ストレージ」タブで個別に確認・削除できるためここでは扱わない
        //   （メモリタブからの一括削除で意図せず消えるのを防ぐ）
        let tempDirs: [(path: String, name: String, desc: String)] = [
            ("/tmp", "システム一時ファイル (/tmp)", "1時間以上前の一時ファイルのみ削除（安全）"),
            ("\(home)/.Trash", "ゴミ箱", "削除済みファイル（完全に消去可能）"),
        ]

        for dir in tempDirs {
            let size = getDirectorySizeMB(dir.path)
            if size > 10 { // Only show directories > 10MB
                items.append((path: dir.path, name: dir.name, sizeMB: size, description: dir.desc))
            }
        }

        return items.sorted { $0.sizeMB > $1.sizeMB }
    }

    /// 一時ファイルを実際に削除する。表示一覧と一致する安全な対象のみ削除する。
    /// （/var/folders やキャッシュ/ログは対象外）
    func clearTempFiles() async -> Double {
        var freedMB: Double = 0

        // /tmp: 1時間以上前のものだけ（使用中のソケット/ロックを避ける）
        let tmpPath = "/tmp"
        if let contents = try? fileManager.contentsOfDirectory(atPath: tmpPath) {
            for item in contents {
                let fullPath = "\(tmpPath)/\(item)"
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let modDate = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(modDate) > 3600 {
                    let size = getItemSizeMB(fullPath)
                    if (try? fileManager.removeItem(atPath: fullPath)) != nil { freedMB += size }
                }
            }
        }

        // ゴミ箱を空にする
        freedMB += await emptyTrash()

        return freedMB
    }

    /// Empty the user's Trash
    func emptyTrash() async -> Double {
        let trashPath = "\(NSHomeDirectory())/.Trash"
        let sizeBefore = getDirectorySizeMB(trashPath)

        if let contents = try? fileManager.contentsOfDirectory(atPath: trashPath) {
            for item in contents {
                try? fileManager.removeItem(atPath: "\(trashPath)/\(item)")
            }
        }

        // 実際に減った分だけを解放量として返す（ロック中等で消えなかった分は除外）
        return max(0, sizeBefore - getDirectorySizeMB(trashPath))
    }

    // MARK: - Login Items Detection

    /// Represents a login item (app that launches at startup)
    struct LoginItem {
        let name: String
        let path: String
        let bundleIdentifier: String?
        let isRunning: Bool
        let memoryMB: Double
    }

    /// Get login items (apps that start at login) using SMAppService if available, fallback to LaunchAgents
    func getLoginItems(processes: [ProcessMemoryInfo]) -> [LoginItem] {
        var items: [LoginItem] = []

        // Scan LaunchAgents directories for plist files
        let launchAgentPaths = [
            "\(NSHomeDirectory())/Library/LaunchAgents",
        ]

        for agentPath in launchAgentPaths {
            guard let files = try? fileManager.contentsOfDirectory(atPath: agentPath) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let fullPath = "\(agentPath)/\(file)"
                if let plist = NSDictionary(contentsOfFile: fullPath),
                   let label = plist["Label"] as? String {
                    // Check if RunAtLoad is true
                    let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
                    guard runAtLoad else { continue }

                    let appName = label
                        .replacingOccurrences(of: "com.", with: "")
                        .replacingOccurrences(of: ".", with: " ")
                        .capitalized

                    // Check if it's currently running and using memory
                    let matchingProcess = processes.first { proc in
                        label.lowercased().contains(proc.name.lowercased()) ||
                        proc.name.lowercased().contains(label.components(separatedBy: ".").last?.lowercased() ?? "")
                    }

                    items.append(LoginItem(
                        name: appName,
                        path: fullPath,
                        bundleIdentifier: label,
                        isRunning: matchingProcess != nil,
                        memoryMB: matchingProcess?.memoryMB ?? 0
                    ))
                }
            }
        }

        // Also check running apps with LSUIElement (background-only apps)
        let runningApps = NSWorkspace.shared.runningApplications
        let bgApps = runningApps.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            // Known startup apps not in LaunchAgents
            let knownStartupBundleIDs: Set<String> = [
                "com.spotify.client", "com.tinyspeck.slackmacgap",
                "com.hnc.Discord", "com.docker.docker",
                "com.getdropbox.dropbox", "com.microsoft.OneDrive",
                "com.google.GoogleDrive", "com.adobe.acc.AdobeCreativeCloud",
                "us.zoom.xos", "com.microsoft.teams2",
            ]
            return knownStartupBundleIDs.contains(bundleID)
        }

        for app in bgApps {
            let appName = app.localizedName ?? "Unknown"
            // Check if already found via LaunchAgents
            if items.contains(where: { $0.name.lowercased().contains(appName.lowercased()) }) { continue }

            let matchingProcess = processes.first { $0.name.contains(appName) }

            items.append(LoginItem(
                name: appName,
                path: app.bundleURL?.path ?? "",
                bundleIdentifier: app.bundleIdentifier,
                isRunning: true,
                memoryMB: matchingProcess?.memoryMB ?? 50
            ))
        }

        return items.filter { $0.memoryMB > 20 }.sorted { $0.memoryMB > $1.memoryMB }
    }

    // MARK: - Browser Cache Analysis

    /// Get browser cache sizes
    func getBrowserCacheInfo() -> [(browser: String, path: String, sizeMB: Double)] {
        let home = NSHomeDirectory()
        var caches: [(browser: String, path: String, sizeMB: Double)] = []

        // Chrome cache
        let chromeCachePaths = [
            "\(home)/Library/Caches/Google/Chrome/Default/Cache",
            "\(home)/Library/Caches/Google/Chrome/Default/Code Cache",
            "\(home)/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage",
        ]
        var chromeTotal: Double = 0
        for path in chromeCachePaths {
            chromeTotal += getDirectorySizeMB(path)
        }
        if chromeTotal > 50 {
            caches.append(("Google Chrome キャッシュ", chromeCachePaths[0], chromeTotal))
        }

        // Safari cache
        let safariCachePaths = [
            "\(home)/Library/Caches/com.apple.Safari",
            "\(home)/Library/Caches/com.apple.Safari.SafeBrowsing",
        ]
        var safariTotal: Double = 0
        for path in safariCachePaths {
            safariTotal += getDirectorySizeMB(path)
        }
        if safariTotal > 30 {
            caches.append(("Safari キャッシュ", safariCachePaths[0], safariTotal))
        }

        // Firefox cache
        let firefoxCache = "\(home)/Library/Caches/Firefox/Profiles"
        let firefoxSize = getDirectorySizeMB(firefoxCache)
        if firefoxSize > 50 {
            caches.append(("Firefox キャッシュ", firefoxCache, firefoxSize))
        }

        // Arc cache
        let arcCache = "\(home)/Library/Caches/company.thebrowser.Browser"
        let arcSize = getDirectorySizeMB(arcCache)
        if arcSize > 50 {
            caches.append(("Arc キャッシュ", arcCache, arcSize))
        }

        return caches.sorted { $0.sizeMB > $1.sizeMB }
    }

    /// Clear a specific browser cache directory
    func clearBrowserCache(path: String) -> Double {
        let sizeBefore = getDirectorySizeMB(path)
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            for file in contents {
                try? fileManager.removeItem(atPath: "\(path)/\(file)")
            }
        }
        // 実際に減った分だけを返す
        return max(0, sizeBefore - getDirectorySizeMB(path))
    }

    // MARK: - Safari Tab Analysis

    /// Fetch Safari tabs via AppleScript
    func fetchSafariTabs() async -> [(title: String, url: String, index: Int, windowIndex: Int)] {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            set tabList to {}
            set windowCount to count of windows
            repeat with w from 1 to windowCount
                set tabCount to count of tabs of window w
                repeat with t from 1 to tabCount
                    set tabName to name of tab t of window w
                    set tabURL to URL of tab t of window w
                    set end of tabList to (w as text) & "|||" & (t as text) & "|||" & tabName & "|||" & tabURL
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return tabList as text
        end tell
        """

        guard let result = await runAppleScript(script), !result.isEmpty else { return [] }

        var tabs: [(title: String, url: String, index: Int, windowIndex: Int)] = []
        for line in result.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }
            let wIndex = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 1
            let tIndex = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1
            // URLは末尾・タイトルは中間結合（タイトルに "|||" が含まれても取り違えない）
            let url = parts[parts.count - 1]
            let title = parts[2..<(parts.count - 1)].joined(separator: "|||")
            tabs.append((title: title, url: url, index: tIndex, windowIndex: wIndex))
        }
        return tabs
    }

    /// Close a Safari tab
    func closeSafariTab(windowIndex: Int, tabIndex: Int) async -> Bool {
        let script = """
        tell application "Safari"
            try
                close tab \(tabIndex) of window \(windowIndex)
                return "success"
            on error
                return "error"
            end try
        end tell
        """
        let result = await runAppleScript(script)
        return result == "success"
    }

    // MARK: - Swap Analysis

    /// Detailed swap information
    struct SwapInfo {
        let usedMB: Double
        let totalMB: Double
        let isExcessive: Bool   // > 2GB or > 50% of RAM
        let topSwappers: [String]
    }

    /// Get detailed swap usage info
    func getSwapInfo(systemMemory: SystemMemoryInfo, processes: [ProcessMemoryInfo]) -> SwapInfo {
        let swapUsed = systemMemory.swapUsedMB
        let isExcessive = swapUsed > 2048 || swapUsed > systemMemory.totalMB * 0.5

        // Processes most likely causing swap (high memory usage + compressed)
        let topSwappers = processes
            .filter { !$0.isSystemProcess && $0.memoryMB > 200 }
            .sorted { $0.memoryMB > $1.memoryMB }
            .prefix(5)
            .map { $0.name }

        return SwapInfo(
            usedMB: swapUsed,
            totalMB: systemMemory.totalMB,
            isExcessive: isExcessive,
            topSwappers: Array(topSwappers)
        )
    }

    // MARK: - Chrome Extension Detection

    /// Detect Chrome extensions and estimate their memory footprint
    func getChromeExtensions() -> [(name: String, id: String, sizeMB: Double)] {
        let extensionsPath = "\(NSHomeDirectory())/Library/Application Support/Google/Chrome/Default/Extensions"
        var extensions: [(name: String, id: String, sizeMB: Double)] = []

        guard let ids = try? fileManager.contentsOfDirectory(atPath: extensionsPath) else { return [] }

        for extID in ids {
            let extPath = "\(extensionsPath)/\(extID)"
            let sizeMB = getDirectorySizeMB(extPath)
            guard sizeMB > 1 else { continue }

            // Try to get extension name from manifest.json
            var extName = extID
            if let versions = try? fileManager.contentsOfDirectory(atPath: extPath),
               let latestVersion = versions.sorted().last {
                let manifestPath = "\(extPath)/\(latestVersion)/manifest.json"
                if let data = fileManager.contents(atPath: manifestPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["name"] as? String {
                    // Some names start with "__MSG_" which are localized — skip those
                    if !name.hasPrefix("__MSG_") {
                        extName = name
                    }
                }
            }

            extensions.append((name: extName, id: extID, sizeMB: sizeMB))
        }

        return extensions.sorted { $0.sizeMB > $1.sizeMB }
    }

    // MARK: - Batch Optimization

    /// Execute a list of optimization suggestions
    func executeOptimizations(_ suggestions: [OptimizationSuggestion]) async -> OptimizationResult {
        var freedMB: Double = 0
        var closedTabs = 0
        var quitApps: [String] = []
        var purged = false

        for suggestion in suggestions {
            let success = await suggestion.action()
            if success {
                freedMB += suggestion.estimatedSavingMB
                switch suggestion.type {
                case .closeTab, .closeSafariTab:
                    closedTabs += 1
                case .quitApp:
                    quitApps.append(suggestion.title)
                case .purgeRAM:
                    purged = true
                default:
                    break
                }
            }
        }

        return OptimizationResult(
            freedMB: freedMB,
            closedTabs: closedTabs,
            quitApps: quitApps,
            purged: purged
        )
    }

    // MARK: - Helpers

    private func runShellCommand(_ path: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    print("Command failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func runAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }

    func getDirectorySizeMB(_ path: String) -> Double {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var totalSize: UInt64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = "\(path)/\(file)"
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? UInt64 {
                totalSize += fileSize
            }
        }
        return Double(totalSize) / 1024 / 1024
    }

    private func getItemSizeMB(_ path: String) -> Double {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            return getDirectorySizeMB(path)
        } else {
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64 {
                return Double(size) / 1024 / 1024
            }
            return 0
        }
    }
}
