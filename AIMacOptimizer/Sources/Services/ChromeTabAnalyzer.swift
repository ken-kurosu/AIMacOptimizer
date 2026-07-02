import Foundation
import AppKit

/// Analyzes Chrome tabs via AppleScript and categorizes them
final class ChromeTabAnalyzer {

    /// Check if Chrome is running before accessing it
    private func isChromeRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.google.Chrome"
        }
    }

    /// Fetch all open Chrome tabs using AppleScript
    func fetchTabs() async -> [ChromeTab] {
        guard isChromeRunning() else {
            print("Chrome is not running, skipping tab analysis")
            return []
        }

        let script = """
        tell application "Google Chrome"
            set tabList to {}
            set windowCount to count of windows
            repeat with w from 1 to windowCount
                set tabCount to count of tabs of window w
                repeat with t from 1 to tabCount
                    set tabTitle to title of tab t of window w
                    set tabURL to URL of tab t of window w
                    set end of tabList to (w as text) & "|||" & (t as text) & "|||" & tabTitle & "|||" & tabURL
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return tabList as text
        end tell
        """

        guard let result = await runAppleScript(script) else { return [] }

        var tabs: [ChromeTab] = []
        let lines = result.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }

            let windowIndex = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
            let tabIndex = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            // タイトルに区切り文字 "|||" が含まれてもURLを取り違えないよう、URLは末尾・タイトルは中間結合
            let url = parts[parts.count - 1]
            let title = parts[2..<(parts.count - 1)].joined(separator: "|||")

            var tab = ChromeTab(
                id: index,
                title: title,
                url: url,
                windowIndex: windowIndex,
                tabIndex: tabIndex
            )
            tab.category = categorize(title: title, url: url)
            tabs.append(tab)
        }

        return tabs
    }

    /// Close a specific Chrome tab via AppleScript
    func closeTab(_ tab: ChromeTab) async -> Bool {
        let script = """
        tell application "Google Chrome"
            try
                close tab \(tab.tabIndex) of window \(tab.windowIndex)
                return "success"
            on error
                return "error"
            end try
        end tell
        """
        let result = await runAppleScript(script)
        return result == "success"
    }

    /// Close multiple tabs at once
    func closeTabs(_ tabs: [ChromeTab]) async -> Int {
        var closed = 0
        // Close in reverse order to avoid index shifting
        let sorted = tabs.sorted { ($0.windowIndex, $0.tabIndex) > ($1.windowIndex, $1.tabIndex) }
        for tab in sorted {
            if await closeTab(tab) {
                closed += 1
            }
        }
        return closed
    }

    // MARK: - Rule-based Tab Categorization

    /// Categorize a tab based on URL and title patterns
    private func categorize(title: String, url: String) -> TabCategory {
        let lowTitle = title.lowercased()
        let lowURL = url.lowercased()

        // Definitely closeable
        if isDefinitelyCloseable(title: lowTitle, url: lowURL) {
            return .closeable
        }

        // Likely work-related
        if isWorkRelated(title: lowTitle, url: lowURL) {
            return .working
        }

        // Everything else needs review
        return .needsReview
    }

    private func isDefinitelyCloseable(title: String, url: String) -> Bool {
        // Empty / new tabs
        if title == "new tab" || title == "新しいタブ" || url == "chrome://newtab/" {
            return true
        }

        // Error pages
        let errorPatterns = [
            "アクセスが拒否", "access denied", "404", "not found",
            "page not found", "err_", "この接続ではプライバシー",
            "このサイトにアクセスできません"
        ]
        if errorPatterns.contains(where: { title.contains($0) || url.contains($0) }) {
            return true
        }

        // Login pages (stale sessions)
        let loginPatterns = ["login", "signin", "sign-in", "auth", "oauth", "/u/login"]
        if loginPatterns.contains(where: { url.contains($0) }) {
            return true
        }

        // Chrome internal pages
        if url.hasPrefix("chrome://") && url != "chrome://extensions/" {
            return true
        }

        // Search result pages
        if url.contains("google.com/search") || url.contains("bing.com/search") {
            return true
        }

        // Duplicate detection: handled at the analyzer level
        return false
    }

    private func isWorkRelated(title: String, url: String) -> Bool {
        let workDomains = [
            "docs.google.com", "sheets.google.com", "slides.google.com",
            "mail.google.com", "calendar.google.com",
            "notion.so", "slack.com", "github.com", "gitlab.com",
            "figma.com", "linear.app", "jira.atlassian.com",
            "confluence.atlassian.com", "trello.com",
            "drive.google.com", "dropbox.com",
            "zoom.us", "teams.microsoft.com",
            "analytics.google.com", "lookerstudio.google.com",
            "redash", "metabase"
        ]

        if workDomains.contains(where: { url.contains($0) }) {
            return true
        }

        // Spreadsheets and documents
        let docPatterns = ["スプレッドシート", "spreadsheet", "document", "ドキュメント"]
        if docPatterns.contains(where: { title.contains($0) }) {
            return true
        }

        return false
    }

    // MARK: - Duplicate Detection

    /// Find duplicate tabs (same URL)
    func findDuplicates(in tabs: [ChromeTab]) -> [ChromeTab] {
        var seenURLs: [String: ChromeTab] = [:]
        var duplicates: [ChromeTab] = []

        for tab in tabs {
            if seenURLs[tab.url] != nil {
                duplicates.append(tab)
            } else {
                seenURLs[tab.url] = tab
            }
        }

        return duplicates
    }

    // MARK: - AppleScript Execution

    private func runAppleScript(_ source: String) async -> String? {
        // NSAppleScript はメインスレッド専用（バックグラウンド実行は稀にクラッシュ/失敗する）
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)

                if let error = error {
                    let errorNum = error[NSAppleScript.errorNumber] as? Int ?? -1
                    let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "unknown"
                    print("AppleScript error [\(errorNum)]: \(errorMsg)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }
}
