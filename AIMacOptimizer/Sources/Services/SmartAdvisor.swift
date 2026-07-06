import Foundation

/// Rule-based AI advisor that generates optimization suggestions
final class SmartAdvisor {

    private let chromeAnalyzer = ChromeTabAnalyzer()
    private let optimizer = MemoryOptimizer()

    /// Analyze the current system state and generate suggestions
    func analyze(
        systemMemory: SystemMemoryInfo,
        processes: [ProcessMemoryInfo],
        chromeTabs: [ChromeTab]? = nil
    ) async -> [OptimizationSuggestion] {
        var suggestions: [OptimizationSuggestion] = []

        // 1. Chrome tabs — closeable & duplicate tabs
        if let tabs = chromeTabs {
            let closeableTabs = tabs.filter { $0.category == .closeable }
            let duplicateTabs = chromeAnalyzer.findDuplicates(in: tabs)
            let allCloseable = Set(closeableTabs.map(\.id)).union(duplicateTabs.map(\.id))

            let tabsToClose = tabs.filter { allCloseable.contains($0.id) }
            if !tabsToClose.isEmpty {
                let estimatedMB = Double(tabsToClose.count) * 80

                let tabDetails = tabsToClose.map { tab -> SuggestionDetailItem in
                    let reason = classifyTabReason(tab)
                    return SuggestionDetailItem(
                        name: String(tab.title.prefix(40)),
                        detail: reason + " ブックマーク済みなら安全に閉じられます",
                        sizeMB: 80,
                        isSelected: true,
                        isRecommended: tab.category == .closeable
                    )
                }

                suggestions.append(OptimizationSuggestion(
                    type: .closeTab,
                    title: L10n.suggestCloseChromeTabs(count: tabsToClose.count),
                    description: L10n.estimatedFreeMB(Int(estimatedMB)),
                    estimatedSavingMB: estimatedMB,
                    detailItems: tabDetails,
                    action: { [weak self] selected in
                        guard let self else { return ActionOutcome(succeeded: false) }
                        let targets = zip(tabsToClose, selected).filter { $0.1.isSelected }.map { $0.0 }
                        guard !targets.isEmpty else { return ActionOutcome(succeeded: false) }
                        let closed = await self.chromeAnalyzer.closeTabs(targets)
                        return ActionOutcome(succeeded: closed > 0)
                    }
                ))
            }
        }

        // 2. Safari tabs
        let safariTabs = await optimizer.fetchSafariTabs()
        if safariTabs.count > 5 {
            let closeableSafari = safariTabs.filter { tab in
                let url = tab.url.lowercased()
                let title = tab.title.lowercased()
                return url.contains("about:blank") ||
                    title.contains("favorites") ||
                    url.contains("google.com/search") ||
                    url.contains("bing.com/search") ||
                    title.contains("404") ||
                    title.contains("error") ||
                    title.isEmpty
            }

            if !closeableSafari.isEmpty {
                let estimatedMB = Double(closeableSafari.count) * 60
                let tabDetails = closeableSafari.map { tab -> SuggestionDetailItem in
                    SuggestionDetailItem(
                        name: tab.title.isEmpty ? "(空白タブ)" : String(tab.title.prefix(40)),
                        detail: classifySafariTabReason(title: tab.title, url: tab.url) + " ブックマーク済みなら安全に閉じられます",
                        sizeMB: 60,
                        isSelected: true,
                        isRecommended: true
                    )
                }

                suggestions.append(OptimizationSuggestion(
                    type: .closeSafariTab,
                    title: L10n.suggestCloseSafariTabs(count: closeableSafari.count),
                    description: L10n.estimatedFreeMB(Int(estimatedMB)),
                    estimatedSavingMB: estimatedMB,
                    detailItems: tabDetails,
                    action: { [weak self] selected in
                        guard let self else { return ActionOutcome(succeeded: false) }
                        let targets = zip(closeableSafari, selected).filter { $0.1.isSelected }.map { $0.0 }
                        guard !targets.isEmpty else { return ActionOutcome(succeeded: false) }
                        var closed = 0
                        // Close in reverse order to avoid index shifting
                        let sorted = targets.sorted { ($0.windowIndex, $0.index) > ($1.windowIndex, $1.index) }
                        for tab in sorted {
                            if await self.optimizer.closeSafariTab(windowIndex: tab.windowIndex, tabIndex: tab.index) {
                                closed += 1
                            }
                        }
                        return ActionOutcome(succeeded: closed > 0)
                    }
                ))
            }
        }

        // 3. Background apps
        let backgroundApps = findBackgroundApps(processes)
        if !backgroundApps.isEmpty {
            let totalMB = backgroundApps.reduce(0.0) { $0 + $1.memoryMB }
            let appDetails = backgroundApps.map { app -> SuggestionDetailItem in
                SuggestionDetailItem(
                    name: app.name,
                    detail: "バックグラウンドで動作中。終了しても保存済みデータは消えません。使用中でなければ安全に終了できます",
                    sizeMB: app.memoryMB,
                    isSelected: true,
                    isRecommended: app.memoryMB > 200
                )
            }

            suggestions.append(OptimizationSuggestion(
                type: .quitApp,
                title: L10n.suggestQuitBackgroundApps(count: backgroundApps.count),
                description: L10n.estimatedFreeMB(Int(totalMB)),
                estimatedSavingMB: totalMB,
                detailItems: appDetails,
                action: { [weak self] selected in
                    guard let self else { return ActionOutcome(succeeded: false) }
                    let targets = zip(backgroundApps, selected).filter { $0.1.isSelected }.map { $0.0 }
                    var success = false
                    for app in targets {
                        if self.optimizer.quitApp(name: app.name) { success = true }
                    }
                    return ActionOutcome(succeeded: success)
                }
            ))
        }

        // 4. Memory leak candidates (apps using excessive memory)
        let leakThreshold = max(500, systemMemory.totalMB * 0.05)
        let leakCandidates = processes.filter {
            $0.memoryMB > leakThreshold && !$0.isSystemProcess
        }
        for app in leakCandidates {
            let essentialApps = ["Google Chrome", "Cursor", "Xcode", "Safari"]
            guard !essentialApps.contains(app.name) else { continue }

            // 再起動の解放量は予測しない（実際の解放量は実行後に実測表示）。使用量の事実だけ示す。
            let details = [
                SuggestionDetailItem(
                    name: "\(app.name) のメモリ使用量",
                    detail: "\(app.memoryFormatted) を使用中（全メモリの\(Int(app.memoryMB / systemMemory.totalMB * 100))%）。長時間起動でメモリがたまっている場合、再起動でリセットされます。作業中のデータは事前に保存してください",
                    sizeMB: app.memoryMB,
                    isSelected: true,
                    isRecommended: true
                )
            ]

            suggestions.append(OptimizationSuggestion(
                type: .restartApp,
                title: L10n.suggestRestartApp(app.name),
                description: L10n.suggestAppMemoryUsing(app.memoryFormatted),
                estimatedSavingMB: app.memoryMB,   // 並び替え用（表示はしない。実解放は実測）
                detailItems: details,
                action: { [weak self] selected in
                    guard selected.first?.isSelected ?? true else { return ActionOutcome(succeeded: false) }
                    let ok = await self?.optimizer.restartApp(name: app.name, bundleIdentifier: app.bundleIdentifier) ?? false
                    return ActionOutcome(succeeded: ok)
                }
            ))
        }

        // 5. Browser cache cleanup
        let browserCaches = optimizer.getBrowserCacheInfo()
        if !browserCaches.isEmpty {
            let totalCacheMB = browserCaches.reduce(0.0) { $0 + $1.sizeMB }
            let cacheDetails = browserCaches.map { cache -> SuggestionDetailItem in
                SuggestionDetailItem(
                    name: cache.browser,
                    detail: "キャッシュ \(String(format: "%.0f MB", cache.sizeMB))。削除してもブックマーク・パスワード・履歴には影響しません。安全に削除できます",
                    sizeMB: cache.sizeMB,
                    isSelected: cache.sizeMB > 200,
                    isRecommended: cache.sizeMB > 200
                )
            }

            suggestions.append(OptimizationSuggestion(
                type: .clearBrowserCache,
                title: L10n.suggestClearBrowserCache(count: browserCaches.count),
                description: L10n.estimatedFreeMB(Int(totalCacheMB)),
                estimatedSavingMB: totalCacheMB,
                detailItems: cacheDetails,
                action: { [weak self] selected in
                    guard let self else { return ActionOutcome(succeeded: false) }
                    let targets = zip(browserCaches, selected).filter { $0.1.isSelected }.map { $0.0 }
                    var totalFreed: Double = 0
                    for cache in targets {
                        totalFreed += self.optimizer.clearBrowserCache(path: cache.path)
                    }
                    // キャッシュ削除はディスクを空ける（RAMではない）
                    return ActionOutcome(succeeded: totalFreed > 0, freedDiskMB: totalFreed)
                }
            ))
        }

        // 6. Chrome extensions (info only — heavy extensions)
        let extensions = optimizer.getChromeExtensions()
        let heavyExtensions = extensions.filter { $0.sizeMB > 5 }
        if !heavyExtensions.isEmpty {
            // Each extension also uses ~30-100MB RAM at runtime
            let runtimeEstimate = Double(heavyExtensions.count) * 50
            let extDetails = heavyExtensions.map { ext -> SuggestionDetailItem in
                SuggestionDetailItem(
                    name: ext.name,
                    detail: "ストレージ \(String(format: "%.0f MB", ext.sizeMB)) + ランタイムメモリ約50MB。ここでは自動削除しません。不要なら chrome://extensions で無効化できます",
                    sizeMB: ext.sizeMB + 50,
                    isSelected: false, // don't auto-select — info only
                    isRecommended: ext.sizeMB > 20
                )
            }

            suggestions.append(OptimizationSuggestion(
                type: .clearCache,
                title: L10n.suggestHeavyChromeExtensions(count: heavyExtensions.count),
                description: L10n.suggestRuntimeMemory(Int(runtimeEstimate)),
                estimatedSavingMB: runtimeEstimate,
                detailItems: extDetails,
                action: { _ in ActionOutcome(succeeded: true) } // Info-only — user manually disables in Chrome
            ))
        }

        // 7. Login items using memory
        let loginItems = optimizer.getLoginItems(processes: processes)
        if !loginItems.isEmpty {
            let totalLoginMB = loginItems.reduce(0.0) { $0 + $1.memoryMB }
            let loginDetails = loginItems.map { item -> SuggestionDetailItem in
                SuggestionDetailItem(
                    name: item.name,
                    detail: item.isRunning
                        ? "\(String(format: "%.0f MB", item.memoryMB)) 使用中。ここでは自動無効化しません。システム設定 > ログイン項目 で手動無効化できます"
                        : "ログイン時に自動起動・現在停止中。無効化はシステム設定から行えます",
                    sizeMB: item.memoryMB,
                    isSelected: false, // don't auto-select — user decides
                    isRecommended: item.memoryMB > 100
                )
            }

            suggestions.append(OptimizationSuggestion(
                type: .disableLoginItem,
                title: L10n.suggestReviewLoginItems(count: loginItems.count),
                description: L10n.suggestLoginItemsUsing(Int(totalLoginMB)),
                estimatedSavingMB: totalLoginMB * 0.5, // Not all will be disabled
                detailItems: loginDetails,
                action: { _ in ActionOutcome(succeeded: true) } // Info-only — user disables in System Settings
            ))
        }

        // 8. Temporary files
        let tempFiles = optimizer.getTempFileInfo()
        if !tempFiles.isEmpty {
            let totalTempMB = tempFiles.reduce(0.0) { $0 + $1.sizeMB }
            if totalTempMB > 100 {
                let tempDetails = tempFiles.map { temp -> SuggestionDetailItem in
                    let isTrash = temp.name.contains("ゴミ箱")
                    return SuggestionDetailItem(
                        name: temp.name,
                        // ゴミ箱を空にするのは取り消せない完全削除なので、デフォルトでは選択しない。
                        // /tmp（再起動で消える一時ファイル）のみデフォルト選択。
                        detail: classifyTempFileDetail(temp),
                        sizeMB: temp.sizeMB,
                        isSelected: !isTrash && temp.name.contains("/tmp"),
                        isRecommended: !isTrash && temp.sizeMB > 500
                    )
                }

                suggestions.append(OptimizationSuggestion(
                    type: .clearTmpFiles,
                    title: L10n.suggestClearTmpFiles,
                    description: L10n.estimatedFreeMB(Int(totalTempMB)),
                    estimatedSavingMB: totalTempMB * 0.7, // Won't delete everything
                    detailItems: tempDetails,
                    action: { [weak self] selected in
                        guard let self else { return ActionOutcome(succeeded: false) }
                        // チェックされた対象だけを削除する（ゴミ箱と/tmpを取り違えない）
                        let clearTrash = zip(tempFiles, selected)
                            .contains { $0.0.name.contains("ゴミ箱") && $0.1.isSelected }
                        let clearTmp = zip(tempFiles, selected)
                            .contains { $0.0.name.contains("/tmp") && $0.1.isSelected }
                        guard clearTrash || clearTmp else { return ActionOutcome(succeeded: false) }
                        let freed = await self.optimizer.clearTempFiles(clearTmp: clearTmp, clearTrash: clearTrash)
                        // 一時ファイル/ゴミ箱の削除はディスクを空ける（RAMではない）
                        return ActionOutcome(succeeded: freed > 0, freedDiskMB: freed)
                    }
                ))
            }
        }

        // 9. DNS cache flush + Font cache (safe mode only)
        let dnsEstimate: Double = 15
        let dnsDetails = [
            SuggestionDetailItem(
                name: "DNSキャッシュ",
                detail: "名前解決のキャッシュを削除。安全に削除でき、ネットワーク問題の解消にも有効です。削除後は自動再構築されます",
                sizeMB: 15,
                isSelected: true,
                isRecommended: true
            ),
            SuggestionDetailItem(
                name: "フォントキャッシュ（安全モード）",
                detail: "フォントサーバーのメモリキャッシュのみフラッシュします。フォントファイルは削除しません。⚠️ フォントDB削除はブラウザのフォント読み込みに影響するため行いません",
                sizeMB: 10,
                isSelected: false,  // デフォルトOFF — ユーザーが明示的に選択
                isRecommended: false
            )
        ]

        suggestions.append(OptimizationSuggestion(
            type: .flushDNS,
            title: L10n.suggestClearDNSCache,
            description: L10n.estimatedFreeMB(Int(dnsEstimate)),
            estimatedSavingMB: dnsEstimate,
            detailItems: dnsDetails,
            action: { [weak self] selected in
                guard let self else { return ActionOutcome(succeeded: false) }
                let dnsOn = selected.first?.isSelected ?? true
                let fontOn = selected.count > 1 ? selected[1].isSelected : false
                var ok = false
                if dnsOn, await self.optimizer.flushDNSCache() { ok = true }
                // Font cache: safe mode only (flush in-memory, no file deletion)
                if fontOn, await self.optimizer.clearFontCache(level: .safe) { ok = true }
                return ActionOutcome(succeeded: ok)
            }
        ))

        // 10. Swap warning (if excessive)
        let swapInfo = optimizer.getSwapInfo(systemMemory: systemMemory, processes: processes)
        if swapInfo.isExcessive {
            // 高メモリアプリを実メモリ付きで提示し、選択したものを実際に終了できるようにする
            let swappers = swapInfo.topSwappers
            let swapDetails = swappers.map { proc -> SuggestionDetailItem in
                SuggestionDetailItem(
                    name: proc.name,
                    detail: "メモリ \(proc.memoryFormatted) を使用。終了すればSwapが減り改善しますが、作業中のデータは先に保存してください",
                    sizeMB: proc.memoryMB,
                    isSelected: false,
                    isRecommended: proc.memoryMB > 500
                )
            }
            let swapUsedFmt = swapInfo.usedMB >= 1024
                ? String(format: "%.1f GB", swapInfo.usedMB / 1024)
                : String(format: "%.0f MB", swapInfo.usedMB)
            let totalSwapperMB = swappers.reduce(0.0) { $0 + $1.memoryMB }

            suggestions.append(OptimizationSuggestion(
                type: .swapWarning,
                title: L10n.suggestSwapHigh(swapUsedFmt),
                description: L10n.suggestSwapHighDesc,
                estimatedSavingMB: totalSwapperMB,
                detailItems: swapDetails,
                action: { [weak self] selected in
                    guard let self else { return ActionOutcome(succeeded: false) }
                    let targets = zip(swappers, selected).filter { $0.1.isSelected }.map { $0.0 }
                    guard !targets.isEmpty else { return ActionOutcome(succeeded: false) }
                    var ok = false
                    for proc in targets {
                        if self.optimizer.quitApp(name: proc.name) { ok = true }
                    }
                    return ActionOutcome(succeeded: ok)
                }
            ))
        }

        // 11. RAM purge は提案しない。
        //   `/usr/sbin/purge` は管理者権限が無いと必ず失敗し(Operation not permitted)、
        //   仮に動いても本アプリの空きメモリ指標(inactiveを既に空き扱い)ではほぼ0にしか反映されない。
        //   「推定○○MB解放」と表示して実際は0、という乖離を生むため、ユーザー向け提案から除外する。
        //   メモリ解放は「実測できるアプリ終了・タブ/キャッシュ削除」で行う。

        // Sort by estimated savings (highest first), but swap warning always at top if present
        return suggestions.sorted { a, b in
            if a.type == .swapWarning { return true }
            if b.type == .swapWarning { return false }
            return a.estimatedSavingMB > b.estimatedSavingMB
        }
    }

    // MARK: - Background App Detection

    /// Find apps that are likely running in the background and not actively used
    private func findBackgroundApps(_ processes: [ProcessMemoryInfo]) -> [ProcessMemoryInfo] {
        let knownBackgroundApps: Set<String> = [
            "Adobe Creative Cloud", "Creative Cloud Helper",
            "Spotify", "Spotify Helper",
            "Discord", "Discord Helper",
            "Amazon Music",
            "LINE", "LINE Helper",
            "Docker Desktop", "Docker",
            "Dropbox", "OneDrive", "Google Drive",
            "Todoist", "Fantastical",
            "Zoom", "zoom.us",
            "Microsoft Teams", "Teams",
            "Notion", "Notion Helper",
            "Steam", "Steam Helper",
            "Epic Games", "Battle.net",
        ]

        return processes.filter { proc in
            !proc.isSystemProcess &&
            proc.memoryMB > 50 &&
            knownBackgroundApps.contains(where: { proc.name.contains($0) })
        }
    }

    // MARK: - Tab Classification

    private func classifyTabReason(_ tab: ChromeTab) -> String {
        if tab.url == "chrome://newtab/" { return "空の新しいタブ — 閉じる推奨" }
        if tab.url.contains("login") || tab.url.contains("auth") { return "ログインページ — 再ログイン不要なら閉じる推奨" }
        if tab.title.contains("404") || tab.title.lowercased().contains("error") { return "エラーページ — 閉じる推奨" }
        if tab.title.lowercased().contains("not found") { return "ページ未検出 — 閉じる推奨" }
        if tab.url.contains("google.com/search") || tab.url.contains("bing.com/search") { return "検索結果ページ — 閲覧済みなら閉じる推奨" }
        if tab.category == .closeable { return "長時間未使用 — 閉じる推奨" }
        return "重複タブ — 1つだけ残せば十分"
    }

    /// Classify temp file items with safety guidance
    private func classifyTempFileDetail(_ temp: (path: String, name: String, sizeMB: Double, description: String)) -> String {
        let sizePart = String(format: "%.0f MB", temp.sizeMB)
        let name = temp.name.lowercased()

        if name.contains("ゴミ箱") || name.contains("trash") {
            return "\(sizePart)。ゴミ箱の中身は既に削除済みのファイルです。安全に完全削除できます"
        }
        if name.contains("/tmp") || name.contains("一時") {
            return "\(sizePart)。システム一時ファイルで再起動時に自動削除されるものです。安全に削除できます"
        }
        if name.contains("cache") || name.contains("キャッシュ") {
            return "\(sizePart)。アプリのキャッシュデータ。削除しても自動再生成されます。安全に削除できます"
        }
        if name.contains("log") || name.contains("ログ") {
            return "\(sizePart)。アプリやシステムのログ。トラブル調査中でなければ安全に削除できます"
        }
        // Default
        return "\(temp.description) — \(sizePart)。通常は安全に削除できますが、心配な場合はスキップしても問題ありません"
    }

    private func classifySafariTabReason(title: String, url: String) -> String {
        if url.contains("about:blank") || title.isEmpty { return "空白タブ — 閉じる推奨" }
        if title.contains("404") || title.lowercased().contains("error") { return "エラーページ — 閉じる推奨" }
        if url.contains("google.com/search") || url.contains("bing.com/search") { return "検索結果ページ — 閉じる推奨" }
        if title.lowercased().contains("favorites") { return "お気に入りページ — 閉じる推奨" }
        return "不要なタブ"
    }
}
