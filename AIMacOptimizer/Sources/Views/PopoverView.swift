import SwiftUI
import AppKit

/// 通知タップ等から「ポップオーバーの表示タブ」を外部指定するための共有ナビ
final class PopoverNavigation: ObservableObject {
    static let shared = PopoverNavigation()
    /// 表示したいタブ(0=メモリ,1=ストレージ,2=診断,3=ツール)。処理後 nil に戻す
    @Published var requestedTab: Int?
    private init() {}
}

/// Main popover view with Memory, Storage, and Diagnosis tabs
struct PopoverView: View {
    @ObservedObject var monitor: ProcessMonitor
    @StateObject private var license = LicenseManager.shared
    @StateObject private var diagnosisEngine: DeepDiagnosisEngine
    @StateObject private var chatService = AIChatService()
    @StateObject private var batteryMonitor = BatteryMonitor()
    @ObservedObject private var popNav = PopoverNavigation.shared
    @State private var selectedTab = 0
    /// 「設定」タブはウィンドウを開くランチャーなので、実際に表示する内容タブは別管理（チラつき防止）
    @State private var lastContentTab = 0
    @State private var showChat = false

    init(monitor: ProcessMonitor) {
        self._monitor = ObservedObject(wrappedValue: monitor)
        self._diagnosisEngine = StateObject(wrappedValue: DeepDiagnosisEngine(processMonitor: monitor))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showChat {
                AIChatView(chatService: chatService, license: license, onBack: {
                    withAnimation { showChat = false }
                })
            } else {
                // Pro badge or Free tier indicator
                tierBadge

                // Tab Selector（上部セグメント）
                Picker("", selection: $selectedTab) {
                    Text(L10n.memoryUsage).tag(0)
                    Text(L10n.storageUsage).tag(1)
                    Text(L10n.tools).tag(3)
                    Text(L10n.diagnosis).tag(2)
                    Text(L10n.settings).tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedTab) { newValue in
                    // どのタブを見たか（匿名）
                    let tabName = ["memory", "storage", "diagnosis", "tools", "settings"]
                    let idx = [0, 1, 2, 3, 4].firstIndex(of: newValue) ?? 0
                    AnalyticsService.shared.track("tab_view", ["tab": tabName[idx]])
                    // 一番右「設定」は独立ウィンドウで開き、タブ表示は直前の内容へ戻す
                    if newValue == 4 {
                        openSettings()
                        DispatchQueue.main.async { selectedTab = lastContentTab }
                    } else {
                        lastContentTab = newValue
                    }
                }

                if lastContentTab == 0 {
                    MemoryTabView(monitor: monitor, license: license)
                } else if lastContentTab == 1 {
                    StorageTabView(license: license)
                } else if lastContentTab == 3 {
                    ToolsTabView(batteryMonitor: batteryMonitor, license: license)
                } else {
                    DiagnosisView(engine: diagnosisEngine, license: license, onOpenChat: {
                        // Inject diagnosis context into chat
                        if let report = diagnosisEngine.lastReport {
                            chatService.setDiagnosisContext(report)
                        }
                        withAnimation { showChat = true }
                    })
                }
            }
        }
        .frame(width: 320, height: 580)
        // 通知タップ等でタブ指定が来たら切り替える（例: レポート通知→診断タブ）
        .onChange(of: popNav.requestedTab) { newValue in
            guard let t = newValue else { return }
            selectedTab = t
            lastContentTab = t
            popNav.requestedTab = nil
        }
        .onAppear {
            if let t = popNav.requestedTab {
                selectedTab = t
                lastContentTab = t
                popNav.requestedTab = nil
            }
        }
    }

    private var tierBadge: some View {
        HStack(spacing: 6) {
            if license.currentTier.isPro {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(license.currentTier.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            } else {
                HStack(spacing: 4) {
                    Text("Free")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if !license.currentTier.isPro {
                Button(action: { openSettings(initialTab: 1) }) {
                    Text(L10n.upgradeToPro)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Memory Tab

struct MemoryTabView: View {
    @ObservedObject var monitor: ProcessMonitor
    @ObservedObject var license: LicenseManager
    @StateObject private var viewModel = PopoverViewModel()
    @State private var affiliateRecs: [AffiliateRecommendation] = []
    @State private var showAllProcesses = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                memoryGaugeSection
                Divider()
                processListSection
                Divider()

                if !viewModel.suggestions.isEmpty {
                    suggestionsSection
                    Divider()
                }

                // おすすめ（アフィリ）はPro/Free問わず、推奨がある時だけ表示
                if !affiliateRecs.isEmpty {
                    affiliateBannerSection
                    Divider()
                }

                actionSection
            }
        }
        .task {
            await viewModel.loadSuggestions(
                systemMemory: monitor.systemMemory,
                processes: monitor.topProcesses,
                license: license
            )
            // Load affiliate recommendations once (not on every re-render)
            // Pro/Free 問わず表示する（おすすめ商品は有料ユーザーにも掲載してよい）
            if affiliateRecs.isEmpty {
                let storageInfo = StorageAnalyzer().getStorageInfo()
                affiliateRecs = AffiliateManager.shared.getRecommendations(
                    memoryUsagePercent: monitor.systemMemory.usagePercent,
                    storageFreeGB: storageInfo.freeGB,
                    storageTotalGB: storageInfo.totalGB
                )
            }
        }
    }

    // MARK: - Memory Gauge

    private var memoryGaugeSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.memoryUsage)
                    .font(.headline)
                Spacer()
                severityBadge
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: monitor.systemMemory.usagePercent / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: monitor.systemMemory.usagePercent)

                VStack(spacing: 2) {
                    Text("\(Int(monitor.systemMemory.usagePercent))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L10n.used)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            HStack(spacing: 16) {
                memoryDetail(L10n.used, monitor.systemMemory.usedFormatted, .blue)
                memoryDetail(L10n.free, monitor.systemMemory.freeFormatted, .green)
                memoryDetail(L10n.swap, monitor.systemMemory.swapFormatted, .orange)
            }
            .font(.caption)
        }
        .padding()
    }

    private var severityBadge: some View {
        Text(monitor.systemMemory.severity.localizedName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.15))
            .foregroundColor(severityColor)
            .cornerRadius(4)
    }

    private func memoryDetail(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Process List

    private var processListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.topProcesses)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ForEach(showAllProcesses ? Array(monitor.topProcesses) : Array(monitor.topProcesses.prefix(8))) { process in
                processRow(process)
            }

            if monitor.topProcesses.count > 8 {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAllProcesses.toggle() } }) {
                    Text(showAllProcesses ? L10n.showMore : L10n.showTopProcesses(count: monitor.topProcesses.count))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 8)
    }

    private func processRow(_ process: ProcessMemoryInfo) -> some View {
        HStack {
            Circle()
                .fill(process.isSystemProcess ? Color.gray : Color.blue)
                .frame(width: 8, height: 8)

            Text(process.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            GeometryReader { geo in
                let maxMB = monitor.topProcesses.first?.memoryMB ?? 1
                let width = min(geo.size.width, geo.size.width * (process.memoryMB / maxMB))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: process.memoryMB))
                    .frame(width: width, height: 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 60, height: 6)

            Text(process.memoryFormatted)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    // MARK: - Suggestions (Expandable) with Free Limit

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text(L10n.suggestions)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // メモリ最適化提案は全ユーザー無制限（回数制限は撤廃）
            ForEach(Array(viewModel.suggestions.prefix(8).enumerated()), id: \.element.id) { index, suggestion in
                SuggestionExpandableRow(
                    suggestion: $viewModel.suggestions[index]
                )
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Affiliate Banner (Free users only)

    private var affiliateBannerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                Text(L10n.recommendations)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("AD")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(3)
            }
            .padding(.horizontal)
            .padding(.top, 6)

            ForEach(affiliateRecs) { rec in
                Button(action: {
                    AffiliateManager.shared.trackClick(recommendation: rec)
                    if let url = URL(string: rec.affiliateURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(rec.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Text(rec.description)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.04))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                Task { await viewModel.optimize(systemMemory: monitor.systemMemory, processes: monitor.topProcesses, license: license) }
            }) {
                HStack {
                    if viewModel.isOptimizing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(viewModel.isOptimizing ? viewModel.optimizingStatus : L10n.oneClickOptimize)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(viewModel.isOptimizing)

            if let result = viewModel.lastResult {
                Text("✅ " + optimizeResultMessage(result))
                    .font(.caption)
                    .foregroundColor(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation { viewModel.lastResult = nil }
                        }
                    }
            }

            HStack {
                Button(action: { openSettings() }) {
                    Text(L10n.settings)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Button(L10n.quit) {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var gaugeColor: Color {
        switch monitor.systemMemory.severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private var severityColor: Color { gaugeColor }

    private func barColor(for memoryMB: Double) -> Color {
        if memoryMB > 1024 { return .red }
        if memoryMB > 500 { return .orange }
        return .blue
    }

    /// RAM解放とディスク解放を分けて正直に表示する。
    /// （キャッシュ/一時ファイル削除はディスクを空けるがRAMは増えないため、混同しない）
    private func optimizeResultMessage(_ result: MemoryOptimizer.OptimizationResult) -> String {
        func fmt(_ mb: Double) -> String {
            mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
        }
        var parts: [String] = []
        if result.freedMB >= 1 { parts.append(L10n.memoryAmount(fmt(result.freedMB))) }
        if result.freedDiskMB >= 1 { parts.append(L10n.diskAmount(fmt(result.freedDiskMB))) }
        if parts.isEmpty {
            // 実測の増分が誤差レベル（例: パージのみ）の場合は数値を断定しない
            return L10n.optimizeDone
        }
        return L10n.optimizeResult(parts.joined(separator: " ／ "))
    }
}

// MARK: - Suggestion Expandable Row

struct SuggestionExpandableRow: View {
    @Binding var suggestion: OptimizationSuggestion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (tappable)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        // 解放量の「目安」は、実測で数値を出せる操作（アプリ終了・キャッシュ/一時ファイル削除）
                        // に限って表示する。タブ/DNS/拡張/ログイン項目/Swap等は予測が当てにならない、
                        // または情報提供のみで実際は解放しないため、緑の数値は出さない（実測結果は実行後に表示）。
                        if showsSavingEstimate(suggestion) {
                            Text(L10n.maxSavingEstimate(suggestion.savingFormatted))
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    Spacer()

                    if !suggestion.detailItems.isEmpty {
                        Text("\(suggestion.detailItems.filter(\.isSelected).count)/\(suggestion.detailItems.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Expanded detail items
            if isExpanded && !suggestion.detailItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(suggestion.detailItems.enumerated()), id: \.element.id) { index, item in
                        SuggestionDetailRow(item: $suggestion.detailItems[index])
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? Color.gray.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }

    /// 実測で解放量を出せる操作だけ「目安」を表示する。
    /// タブ/再起動/DNS/拡張/ログイン項目/Swap は予測が当てにならない or 情報提供のみのため数値を出さない。
    private func showsSavingEstimate(_ s: OptimizationSuggestion) -> Bool {
        switch s.type {
        case .quitApp, .clearBrowserCache, .clearTmpFiles:
            return s.estimatedSavingMB >= 1
        default:
            return false
        }
    }
}

struct SuggestionDetailRow: View {
    @Binding var item: SuggestionDetailItem

    var body: some View {
        HStack(spacing: 6) {
            // Checkbox
            Button(action: { item.isSelected.toggle() }) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(item.isSelected ? .blue : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundColor(item.isSelected ? .primary : .secondary)

                    if item.isRecommended {
                        Text(L10n.recommended)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            Text(item.sizeFormatted)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Storage Tab (Expandable) with Pro Gating

struct StorageTabView: View {
    @StateObject private var analyzer = StorageAnalyzer()
    @ObservedObject var license: LicenseManager
    @ObservedObject private var diskGuard = DiskGuard.shared
    @State private var confirmSubItems: [StorageSubItem] = []
    @State private var confirmParentName: String = ""
    @State private var confirmAction: StorageAction?
    @State private var confirmCategory: StorageCategory?
    @State private var cleanupMessage: String?
    @State private var enableAutoFromNow = false
    // 拡張ストレージCTAのコピー(CTR最適化用にローテーション)
    @State private var ctaVariant = Int.random(in: 0..<max(1, PurchaseConfig.storageUpgradeCopies.count))

    var body: some View {
        VStack(spacing: 0) {
            // ストレージ圧迫検知時の「安全に空ける」提案バナー
            if let plan = diskGuard.pendingPlan, !plan.isEmpty {
                diskPressureBanner(plan)
            }

            // 自動削除が有効なときは常に状態と「停止」を表示（後から止められるように）
            if diskGuard.settings.autoClean {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.storageAutoCleanEnabled)
                            .font(.system(size: 11, weight: .semibold))
                        Text(L10n.storageAutoCleanDesc)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(L10n.stop) {
                        diskGuard.settings.autoClean = false
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            // Inline confirmation banner (replaces .alert to keep popover open)
            if let action = confirmAction, !confirmSubItems.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        Text(L10n.confirm)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    let totalSizeMB = confirmSubItems.reduce(0.0) { $0 + $1.sizeMB }
                    let sizeStr = totalSizeMB >= 1024
                        ? String(format: "%.1f GB", totalSizeMB / 1024)
                        : String(format: "%.0f MB", totalSizeMB)
                    Text(L10n.confirmStorageAction(parent: confirmParentName, count: confirmSubItems.count, size: sizeStr, action: action.localizedName))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Spacer()
                        Button {
                            confirmSubItems = []
                            confirmAction = nil
                            confirmCategory = nil
                        } label: {
                            Text(L10n.cancel)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            executeConfirmedAction()
                        } label: {
                            Text(action.localizedName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            storageOverview
            iCloudEvictAction
            storageAffiliateCTA
            Divider()

            if analyzer.isScanning {
                Spacer()
                ProgressView(L10n.analyzing)
                Spacer()
            } else if analyzer.items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text(L10n.noSuggestions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(L10n.startScan) {
                    Task { await analyzer.scan() }
                }
                .buttonStyle(.borderedProminent)
                .padding()
            } else {
                // Free tier: show items but lock deletion actions
                if !license.canDeleteStorage {
                    storageProUpgradeBanner
                }
                storageItemsList
            }

            if let message = cleanupMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.contains("❌") ? .red : .green)
                    .padding(.bottom, 8)
                    .onAppear {
                        // Auto-dismiss after 4 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { cleanupMessage = nil }
                        }
                    }
            }
        }
        // 表示時と、削除で空きが変わった時に「〇〇GB空き」を即更新する
        .onAppear { analyzer.storageInfo = analyzer.getStorageInfo() }
        .onChange(of: diskGuard.lastAutoCleanSummary) { _ in
            analyzer.storageInfo = analyzer.getStorageInfo()
        }
    }

    // MARK: - ストレージ圧迫「安全に空ける」提案バナー

    @ViewBuilder
    private func diskPressureBanner(_ plan: SafeCleanupPlan) -> some View {
        let emergency = diskGuard.pressureLevel == .emergency
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: emergency ? "exclamationmark.triangle.fill" : "internaldrive.fill")
                    .foregroundColor(emergency ? .red : .orange)
                    .font(.system(size: 14))
                Text(emergency ? "緊急：空き容量が極めて少ない" : L10n.storagePressureDetected)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(emergency ? .red : .primary)
                Spacer()
                Text(L10n.storageUsageSummary(percent: Int(plan.usagePercentBefore), freeGB: String(format: "%.1f", plan.freeGBBefore)))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // 緊急時は、確実に空く安全コマンド（再生成される項目のみ）もワンタップでコピーできる
            if emergency {
                Button {
                    let joined = DiskGuard.emergencyTerminalCommands.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                    cleanupMessage = "安全コマンドをコピーしました。ターミナルに貼り付けて実行できます。"
                } label: {
                    Label("緊急時の安全コマンドをコピー", systemImage: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(L10n.safeCleanupAvailable(plan.totalFormatted))
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // なぜほぼリスク0か・何を消すのかを明示（データ損失の不安を取り除く）
            Text("対象は、アプリ・ブラウザ・開発ツールが自動で作り直すキャッシュ/ログだけです。写真・書類・アプリ本体・設定・フォントは対象外で、削除してもデータは失われません（各項目の内訳は下に表示）。")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 何を消すか + 安全度の内訳
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.candidates) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: item.safety.icon)
                                .font(.system(size: 9))
                                .foregroundColor(safetyColor(item.safety))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(item.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Text(item.safety.localizedName)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(safetyColor(item.safety))
                                    Spacer()
                                    Text(item.sizeFormatted)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                Text(item.reason)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .scrollIndicators(.visible)

            Toggle(isOn: $enableAutoFromNow) {
                Text(L10n.autoCleanFromNow)
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 10) {
                Button {
                    diskGuard.dismissPendingPlan()
                } label: {
                    Text(L10n.later)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    diskGuard.approvePendingPlan(enableAutoFromNow: enableAutoFromNow)
                    // 実際の解放量は削除完了後に通知でお知らせ（ここでは見込み値を断定しない）
                    cleanupMessage = L10n.cleanupStarted
                } label: {
                    Text(L10n.cleanNowSafely(plan.totalFormatted))
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background((emergency ? Color.red : Color.blue).opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func safetyColor(_ safety: CleanupSafety) -> Color {
        switch safety {
        case .safe: return .green
        case .caution: return .orange
        }
    }

    // MARK: - Pro Upgrade Banner for Storage

    private var storageProUpgradeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.proRequiredForDeletion)
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.scanResultsFreeOK)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { openSettings(initialTab: 1) }) {
                Text(L10n.toPro)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
    }

    // iCloud Drive をローカルから退避（evict）。空きが少ない時に表示。クラウドには残る＝安全
    @ViewBuilder
    private var iCloudEvictAction: some View {
        if analyzer.storageInfo.totalGB > 0, analyzer.storageInfo.freeGB < 20 {
            Button {
                cleanupMessage = "iCloud Driveを退避中…"
                let analyzer = analyzer
                DispatchQueue.global(qos: .userInitiated).async {
                    let freed = analyzer.evictICloudDrive()
                    DispatchQueue.main.async {
                        analyzer.storageInfo = analyzer.getStorageInfo()
                        cleanupMessage = freed > 100
                            ? "iCloud Driveを退避し約\(Int(freed))MB空けました（クラウドには残っています）"
                            : "iCloud Driveの退避を実行しました（反映に少し時間がかかる場合があります）"
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 11)).foregroundColor(.blue)
                    Text("iCloud Driveをローカルから退避（クラウドに残す）")
                        .font(.system(size: 10.5)).foregroundColor(.primary).lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // 拡張ストレージ アフィリCTA（URL未設定なら非表示。空きが少ない時だけ・コピーはローテーション＋匿名計測）
    @ViewBuilder
    private var storageAffiliateCTA: some View {
        if let urlStr = PurchaseConfig.storageUpgradeURL, let url = URL(string: urlStr),
           analyzer.storageInfo.totalGB > 0, analyzer.storageInfo.freeGB < 20 {
            let copies = PurchaseConfig.storageUpgradeCopies
            let copy = copies.isEmpty ? "拡張ストレージを見る" : copies[ctaVariant % copies.count]
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .foregroundColor(.blue)
                    Text(copy)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .onAppear { AnalyticsService.shared.track("storage_cta_impression", ["variant": ctaVariant]) }
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsService.shared.track("storage_cta_click", ["variant": ctaVariant])
            })
        }
    }

    private var storageOverview: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.storageUsage)
                    .font(.headline)
                Spacer()
                Text(analyzer.storageInfo.freeFormatted + " " + L10n.free)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                let usageRatio = analyzer.storageInfo.totalGB > 0
                    ? analyzer.storageInfo.usedGB / analyzer.storageInfo.totalGB
                    : 0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(usageRatio > 0.9 ? Color.red : usageRatio > 0.7 ? Color.orange : Color.blue)
                        .frame(width: geo.size.width * usageRatio)
                }
            }
            .frame(height: 12)

            HStack {
                Text("\(analyzer.storageInfo.usedFormatted) / \(analyzer.storageInfo.totalFormatted)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .onAppear {
            analyzer.storageInfo = analyzer.getStorageInfo()
        }
    }

    private var storageItemsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(analyzer.items.enumerated()), id: \.element.id) { index, item in
                    StorageExpandableRow(
                        item: $analyzer.items[index],
                        analyzer: analyzer,
                        isProUser: license.canDeleteStorage,
                        onSubItemAction: { parentItem, selectedSubs, action in
                            // Gate deletion behind Pro
                            guard license.canDeleteStorage else { return }

                            if parentItem.category == .cache || parentItem.category == .log {
                                let result = analyzer.clearSelectedSubItems(selectedSubs)
                                if result.success > 0 {
                                    cleanupMessage = L10n.clearedCount(result.success)
                                    Task {
                                        await analyzer.scan()
                                        analyzer.storageInfo = analyzer.getStorageInfo()
                                    }
                                }
                            } else {
                                confirmSubItems = selectedSubs
                                confirmParentName = parentItem.name
                                confirmAction = action
                                confirmCategory = parentItem.category
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func executeConfirmedAction() {
        guard let action = confirmAction, !confirmSubItems.isEmpty else { return }

        let result: (success: Int, failed: Int)
        switch action {
        case .delete, .moveToTrash:
            result = analyzer.moveSubItemsToTrash(confirmSubItems)
        case .moveToICloud:
            result = analyzer.moveSubItemsToICloud(confirmSubItems)
        }

        if result.success > 0 {
            cleanupMessage = L10n.actionDoneCount(result.success, action: action.localizedName)
            if result.failed > 0 {
                cleanupMessage! += L10n.actionFailedCount(result.failed)
            }
            Task {
                await analyzer.scan()
                analyzer.storageInfo = analyzer.getStorageInfo()
            }
        } else {
            cleanupMessage = L10n.operationFailed
        }

        confirmSubItems = []
        confirmAction = nil
        confirmCategory = nil
    }
}

// MARK: - Storage Expandable Row

struct StorageExpandableRow: View {
    @Binding var item: StorageItem
    let analyzer: StorageAnalyzer
    let isProUser: Bool
    /// Callback with (parentItem, selectedSubItems, action)
    let onSubItemAction: (StorageItem, [StorageSubItem], StorageAction) -> Void

    @State private var isExpanded = false
    @State private var subItemsLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                // Expand button
                Button(action: {
                    // 展開自体は即反応させ、重いファイルI/O(サブ項目取得)は背景で行ってから反映する
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    if isExpanded && !subItemsLoaded {
                        subItemsLoaded = true
                        let snapshot = item
                        let analyzer = analyzer
                        DispatchQueue.global(qos: .userInitiated).async {
                            let subs = analyzer.getSubItems(for: snapshot)
                            DispatchQueue.main.async { item.subItems = subs }
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: item.category.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                    .font(.system(size: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.category.localizedName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.sizeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Action menu - disabled for Free users
                if isProUser {
                    Menu {
                        if item.category == .cache || item.category == .log {
                            Button(L10n.clearChecked) {
                                let targets = selectedOrAllSubItems()
                                guard !targets.isEmpty else { return }
                                onSubItemAction(item, targets, .delete)
                            }
                            .disabled(subItemsLoaded && item.subItems.filter(\.isSelected).isEmpty)
                        } else {
                            Button(L10n.moveCheckedToTrash) {
                                let targets = selectedOrAllSubItems()
                                guard !targets.isEmpty else { return }
                                onSubItemAction(item, targets, .moveToTrash)
                            }
                            .disabled(subItemsLoaded && item.subItems.filter(\.isSelected).isEmpty)
                            Button(L10n.moveCheckedToICloud) {
                                let targets = selectedOrAllSubItems()
                                guard !targets.isEmpty else { return }
                                onSubItemAction(item, targets, .moveToICloud)
                            }
                            .disabled(subItemsLoaded && item.subItems.filter(\.isSelected).isEmpty)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)   // 「⋯」の右に出る紛らわしいドロップダウン矢印を消す
                    .fixedSize()
                    .frame(width: 24)
                } else {
                    // Lock icon for Free users
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .frame(width: 24)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Expanded sub-items
            if isExpanded {
                if item.subItems.isEmpty {
                    HStack {
                        Spacer()
                        Text(L10n.noFiles)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.subItems.enumerated()), id: \.element.id) { subIndex, subItem in
                            StorageSubItemRow(subItem: $item.subItems[subIndex])
                        }

                        // Action buttons for selected sub-items (Pro only)
                        if isProUser {
                            let selectedSubs = item.subItems.filter(\.isSelected)
                            if !selectedSubs.isEmpty {
                                Divider().padding(.vertical, 4)
                                HStack(spacing: 8) {
                                    Text(L10n.selectedCount(selectedSubs.count))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if item.category == .cache || item.category == .log {
                                        Button {
                                            onSubItemAction(item, selectedSubs, .delete)
                                        } label: {
                                            Text(L10n.clear)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .controlSize(.small)
                                    } else {
                                        Button {
                                            onSubItemAction(item, selectedSubs, .moveToTrash)
                                        } label: {
                                            Text(L10n.toTrash)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .controlSize(.small)

                                        Button {
                                            onSubItemAction(item, selectedSubs, .moveToICloud)
                                        } label: {
                                            Text(L10n.iCloud)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 36)
                    .padding(.trailing, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(isExpanded ? Color.gray.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }

    /// Returns only checked sub-items. If none expanded yet, treats as whole item selected.
    private func selectedOrAllSubItems() -> [StorageSubItem] {
        if subItemsLoaded && !item.subItems.isEmpty {
            let selected = item.subItems.filter(\.isSelected)
            // Only return checked items — never fall back to all
            return selected
        }
        // Not yet expanded — treat the whole category as one item
        return [StorageSubItem(
            path: item.path, name: item.name, sizeMB: item.sizeMB,
            isSelected: true, isRecommended: true, reason: ""
        )]
    }
}

struct StorageSubItemRow: View {
    @Binding var subItem: StorageSubItem

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { subItem.isSelected.toggle() }) {
                Image(systemName: subItem.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundColor(subItem.isSelected ? .blue : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(subItem.name)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundColor(subItem.isSelected ? .primary : .secondary)

                    if subItem.isRecommended {
                        Text(L10n.recommended)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                if !subItem.reason.isEmpty {
                    Text(subItem.reason)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()

            Text(subItem.sizeFormatted)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Tools Tab (Battery Health + App Uninstaller)
struct ToolsTabView: View {
    @ObservedObject var batteryMonitor: BatteryMonitor
    @ObservedObject var license: LicenseManager
    @StateObject private var uninstaller = AppUninstaller()
    @State private var selectedSection = 0 // 0: battery, 1: uninstaller
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                Text(L10n.battery).tag(0)
                Text(L10n.appManagement).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            if selectedSection == 0 {
                batterySection
            } else {
                uninstallerSection
            }
        }
    }
    
    // MARK: - Battery Health
    private var batterySection: some View {
        ScrollView {
            VStack(spacing: 12) {
                if batteryMonitor.isAvailable {
                    // Battery gauge
                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.batteryHealth)
                                .font(.headline)
                            Spacer()
                            Text(batteryMonitor.conditionLocalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(batteryConditionColor.opacity(0.15))
                                .foregroundColor(batteryConditionColor)
                                .cornerRadius(4)
                        }
                        
                        // Health gauge
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: Double(batteryMonitor.healthPercent) / 100)
                                .stroke(batteryHealthColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Text("\(batteryMonitor.healthPercent)%")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(batteryHealthColor)
                                Text(L10n.healthLevel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 80, height: 80)
                    }
                    .padding()
                    
                    // Battery details grid
                    VStack(spacing: 6) {
                        batteryRow(L10n.chargingStatus, batteryMonitor.isCharging ? L10n.charging : L10n.onBattery,
                                   icon: batteryMonitor.isCharging ? "bolt.fill" : "battery.100")
                        batteryRow(L10n.batteryLevel, "\(batteryMonitor.batteryLevel)%", icon: "battery.75")
                        batteryRow(L10n.chargeCycles, L10n.cycleCountValue(batteryMonitor.cycleCount), icon: "arrow.triangle.2.circlepath")
                        batteryRow(L10n.maxCapacity, "\(batteryMonitor.maxCapacity) mAh", icon: "bolt.batteryblock")
                        batteryRow(L10n.designCapacity, "\(batteryMonitor.designCapacity) mAh", icon: "square.and.pencil")
                        if batteryMonitor.temperature > 0 {
                            batteryRow(L10n.temperature, String(format: "%.1f°C", batteryMonitor.temperature), icon: "thermometer.medium")
                        }
                        if !batteryMonitor.timeRemaining.isEmpty {
                            batteryRow(L10n.timeRemainingLabel, batteryMonitor.timeRemainingLocalized, icon: "clock")
                        }
                    }
                    .padding(.horizontal)
                    
                    // Battery tips
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(L10n.batteryTips)
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(batteryMonitor.cycleCount > 800
                            ? L10n.batteryTipReplace
                            : L10n.batteryTipRange)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 40)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(L10n.noBattery)
                            .font(.headline)
                        Text(L10n.noBatteryDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func batteryRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
    
    private var batteryHealthColor: Color {
        if batteryMonitor.healthPercent >= 80 { return .green }
        if batteryMonitor.healthPercent >= 60 { return .orange }
        return .red
    }
    
    private var batteryConditionColor: Color {
        switch batteryMonitor.conditionKind {
        case .normal, .good: return .green
        case .warning: return .orange
        case .replace: return .red
        case .unknown, .desktop: return .secondary
        }
    }
    
    // MARK: - App Uninstaller
    private var uninstallerSection: some View {
        VStack(spacing: 0) {
            if uninstaller.isScanning {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
                    ProgressView()
                    Text(L10n.scanningApps)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if uninstaller.apps.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                    Text(L10n.appManagement)
                        .font(.headline)
                    Text(L10n.detectLeftovers)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        Task { await uninstaller.scanInstalledApps() }
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(L10n.startScan)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                // App list with leftover info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.appsCount(uninstaller.apps.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        let totalLeftover = uninstaller.apps.reduce(0.0) { $0 + $1.leftoverSizeMB }
                        if totalLeftover > 0 {
                            Text(L10n.leftoverTotal(formatSize(totalLeftover)))
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        Button(action: {
                            Task { await uninstaller.scanInstalledApps() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(uninstaller.apps.filter { $0.leftoverSizeMB > 1 }.prefix(30)) { app in
                            AppUninstallRow(app: app, uninstaller: uninstaller, isProUser: license.currentTier.isPro)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func formatSize(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - App Uninstall Row
struct AppUninstallRow: View {
    let app: InstalledApp
    let uninstaller: AppUninstaller
    let isProUser: Bool
    @State private var isExpanded = false
    @State private var resultMessage: String?
    @State private var pendingAction: PendingUninstallAction?
    /// チェックを外した残留パス（既定は全選択）
    @State private var deselected: Set<String> = []

    /// 確認待ちの破壊的操作
    private enum PendingUninstallAction: Equatable {
        case leftoversOnly  // 残留削除
        case uninstall      // アンインストール
    }

    /// 残留削除で実際に消す対象（選択中のパス）
    private var selectedLeftoverPaths: [String] {
        app.leftovers.map(\.path).filter { !deselected.contains($0) }
    }

    private func leftoverRiskColor(_ risk: LeftoverRisk) -> Color {
        risk == .medium ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // App icon placeholder
                    Image(systemName: "app.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if app.leftoverSizeMB > 0 {
                                Text(L10n.leftoverLabel(formatSize(app.leftoverSizeMB)))
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }
                            Text(L10n.totalLabel(formatSize(app.totalSizeMB)))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // 「残留ファイル」とは何かの説明
                    Text(L10n.leftoverExplanation)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !app.leftovers.isEmpty {
                        Text(L10n.leftoverHeader(count: app.leftovers.count, size: formatSize(app.leftoverSizeMB)))
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(app.leftovers) { item in
                            let isOn = !deselected.contains(item.path)
                            Button(action: {
                                if isOn { deselected.insert(item.path) } else { deselected.remove(item.path) }
                            }) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 11))
                                        .foregroundColor(isOn ? .blue : .gray)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            Text(item.category)
                                                .font(.system(size: 10, weight: .medium))
                                            Text(L10n.leftoverRiskLabel(item.risk.localizedName))
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(leftoverRiskColor(item.risk))
                                            Spacer()
                                            Text(item.sizeFormatted)
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(item.reason)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isProUser {
                        if let pending = pendingAction {
                            confirmPanel(pending)
                        } else {
                            // 2つの選択肢を、効果とリスクつきで提示
                            VStack(alignment: .leading, spacing: 8) {
                                if app.leftoverSizeMB > 0 {
                                    actionChoice(
                                        title: L10n.leftoverRemoveTitle,
                                        tint: .orange,
                                        risk: L10n.riskLow,
                                        desc: L10n.leftoverRemoveDesc,
                                        action: { pendingAction = .leftoversOnly }
                                    )
                                }
                                actionChoice(
                                    title: L10n.uninstallTitle,
                                    tint: .red,
                                    risk: L10n.riskMedium,
                                    desc: L10n.uninstallDesc,
                                    action: { pendingAction = .uninstall }
                                )
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(L10n.proFeature)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.orange)
                    }

                    if let msg = resultMessage {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
            }
        }
        .background(isExpanded ? Color.gray.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private func formatSize(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    /// 選択肢（ボタン＋リスク＋効果説明）
    @ViewBuilder
    private func actionChoice(title: String, tint: Color, risk: String, desc: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: action) {
                    Text(title).font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
                Text(risk)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tint)
            }
            Text(desc)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 実行前の確認パネル（破壊的操作は理解・納得のうえ実行できるように）
    @ViewBuilder
    private func confirmPanel(_ pending: PendingUninstallAction) -> some View {
        let isUninstall = (pending == .uninstall)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isUninstall ? .red : .orange)
                Text(isUninstall ? L10n.uninstallConfirmTitle : L10n.removeLeftoversConfirmTitle)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(isUninstall
                ? L10n.uninstallConfirmDesc(app: app.name)
                : L10n.removeLeftoversConfirmDesc(count: selectedLeftoverPaths.count))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.trashRecoverable)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(L10n.cancel) { pendingAction = nil }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button(isUninstall ? L10n.uninstallAction : L10n.removeLeftoversAction) {
                    executeAction(pending)
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(isUninstall ? .red : .orange)
                .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isUninstall ? Color.red : Color.orange).opacity(0.08))
        .cornerRadius(6)
    }

    private func executeAction(_ pending: PendingUninstallAction) {
        switch pending {
        case .leftoversOnly:
            let result = uninstaller.removeLeftovers(paths: selectedLeftoverPaths)
            resultMessage = L10n.leftoversMovedResult(count: result.removedCount, freed: formatSize(result.freedMB))
                + (result.errors.isEmpty ? "" : L10n.partialFailure(result.errors.count))
        case .uninstall:
            // チェックを外した残留は削除しない（leftoversOnly と同じ選択集合を渡す）
            let result = uninstaller.uninstallApp(app, leftoverPaths: selectedLeftoverPaths)
            resultMessage = result.errors.isEmpty
                ? L10n.appUninstalledResult(app: app.name, count: result.removedCount, freed: formatSize(result.freedMB))
                : L10n.uninstallPartialFailure(success: result.removedCount, errors: result.errors.count)
        }
        pendingAction = nil
    }
}

// MARK: - Settings Helper (macOS 13+ compatible)

/// Open the Settings window using our own window controller
private func openSettings(initialTab: Int? = nil) {
    SettingsWindowController.shared.showSettings(initialTab: initialTab)
}

// MARK: - ViewModel

@MainActor
final class PopoverViewModel: ObservableObject {
    @Published var suggestions: [OptimizationSuggestion] = []
    @Published var isOptimizing = false
    @Published var optimizingStatus: String = ""
    @Published var lastResult: MemoryOptimizer.OptimizationResult?

    private let advisor = SmartAdvisor()
    private let optimizer = MemoryOptimizer()
    private let chromeAnalyzer = ChromeTabAnalyzer()

    /// Types that were recently optimized — hidden from the list temporarily
    private var recentlyOptimizedTypes: Set<SuggestionType> = []

    func loadSuggestions(systemMemory: SystemMemoryInfo, processes: [ProcessMemoryInfo], license: LicenseManager) async {
        // Check if free tier user has remaining suggestions
        guard license.canUseAISuggestions else {
            suggestions = []
            return
        }

        let tabs = await chromeAnalyzer.fetchTabs()
        var newSuggestions = await advisor.analyze(
            systemMemory: systemMemory,
            processes: processes,
            chromeTabs: tabs.isEmpty ? nil : tabs
        )

        // Filter out recently optimized types
        if !recentlyOptimizedTypes.isEmpty {
            newSuggestions = newSuggestions.filter { !recentlyOptimizedTypes.contains($0.type) }
        }

        suggestions = newSuggestions

        // Record usage for free tier
        if !suggestions.isEmpty {
            license.recordAISuggestionUse()
        }
    }

    func optimize(systemMemory: SystemMemoryInfo, processes: [ProcessMemoryInfo], license: LicenseManager) async {
        isOptimizing = true
        lastResult = nil

        // 表示中の候補と選択をそのまま実行する。
        // （以前はここで loadSuggestions を呼び直しており、推定値の再計算と選択リセットで
        //  画面の表示値とボタン下の結果がズレていた）
        if suggestions.isEmpty {
            optimizingStatus = L10n.analyzing
            await loadSuggestions(systemMemory: systemMemory, processes: processes, license: license)
        }

        // 実行対象＝選択ありの候補のみ
        let toExecute = suggestions.filter { $0.detailItems.isEmpty || $0.detailItems.contains(where: \.isSelected) }
        let executedTypes = Set(toExecute.map(\.type))

        optimizingStatus = L10n.optimizing(count: toExecute.count)
        lastResult = await optimizer.executeOptimizations(toExecute)

        // Mark executed types as recently optimized
        recentlyOptimizedTypes = executedTypes

        // Remove executed suggestions from the current list immediately
        suggestions.removeAll { executedTypes.contains($0.type) }

        optimizingStatus = ""
        isOptimizing = false

        // Clear the recently optimized filter after 60 seconds so they can reappear on next analysis
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            recentlyOptimizedTypes.removeAll()
        }
    }
}
