import SwiftUI

/// Main popover view with Memory, Storage, and Diagnosis tabs
struct PopoverView: View {
    @ObservedObject var monitor: ProcessMonitor
    @StateObject private var license = LicenseManager.shared
    @StateObject private var diagnosisEngine: DeepDiagnosisEngine
    @StateObject private var chatService = AIChatService()
    @StateObject private var batteryMonitor = BatteryMonitor()
    @State private var selectedTab = 0
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
                    Text("ツール").tag(3)
                    Text(L10n.diagnosis).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedTab == 0 {
                    MemoryTabView(monitor: monitor, license: license)
                } else if selectedTab == 1 {
                    StorageTabView(license: license)
                } else if selectedTab == 3 {
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
    }

    private var tierBadge: some View {
        HStack(spacing: 6) {
            if license.currentTier.isPro {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(license.currentTier.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.15))
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
                    Text("Pro にアップグレード")
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
        Text(monitor.systemMemory.severity.rawValue)
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
                    Text(showAllProcesses ? "閉じる" : "もっと見る（上位\(monitor.topProcesses.count)件）")
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
                Text("おすすめ")
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
        if result.freedMB >= 1 { parts.append("メモリ約 \(fmt(result.freedMB))") }
        if result.freedDiskMB >= 1 { parts.append("ディスク約 \(fmt(result.freedDiskMB))") }
        if parts.isEmpty {
            // 実測の増分が誤差レベル（例: パージのみ）の場合は数値を断定しない
            return "最適化を実行しました"
        }
        return parts.joined(separator: " ／ ") + " を解放しました"
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
                        // 上限の目安であることを明示（実際の解放量は実行後に実測値で表示する）
                        Text("最大 約\(suggestion.savingFormatted)（目安）")
                            .font(.caption2)
                            .foregroundColor(.green)
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
                        Text("推奨")
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
                        Text("ストレージ自動削除: 有効")
                            .font(.system(size: 11, weight: .semibold))
                        Text("圧迫時に安全なキャッシュ/ログを自動削除し通知します")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("停止") {
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
                        Text("確認")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }

                    let totalSizeMB = confirmSubItems.reduce(0.0) { $0 + $1.sizeMB }
                    let sizeStr = totalSizeMB >= 1024
                        ? String(format: "%.1f GB", totalSizeMB / 1024)
                        : String(format: "%.0f MB", totalSizeMB)
                    Text("\(confirmParentName) から \(confirmSubItems.count)件 (\(sizeStr)) を\(action.rawValue)しますか？")
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
                            Text("キャンセル")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            executeConfirmedAction()
                        } label: {
                            Text(action.rawValue)
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

                Button("スキャン開始") {
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
    }

    // MARK: - ストレージ圧迫「安全に空ける」提案バナー

    @ViewBuilder
    private func diskPressureBanner(_ plan: SafeCleanupPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("ストレージ圧迫を検知")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("使用 \(Int(plan.usagePercentBefore))% / 空き \(String(format: "%.1f", plan.freeGBBefore))GB")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Text("リスクのないキャッシュ/ログを約 \(plan.totalFormatted) 安全に削除できます。")
                .font(.system(size: 11))
                .foregroundColor(.primary)
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
                                    Text(item.safety.rawValue)
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
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 110)

            Toggle(isOn: $enableAutoFromNow) {
                Text("今後、圧迫を検知したら自動で空ける（通知のみ）")
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 10) {
                Button {
                    diskGuard.dismissPendingPlan()
                } label: {
                    Text("後で")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    diskGuard.approvePendingPlan(enableAutoFromNow: enableAutoFromNow)
                    // 実際の解放量は削除完了後に通知でお知らせ（ここでは見込み値を断定しない）
                    cleanupMessage = "ストレージの掃除を実行しました（結果は通知でお知らせします）"
                } label: {
                    Text("今すぐ安全に空ける（\(plan.totalFormatted)）")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
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
                Text("削除にはProが必要です")
                    .font(.system(size: 11, weight: .semibold))
                Text("スキャン結果の確認はFreeでもOK")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { openSettings(initialTab: 1) }) {
                Text("Pro へ")
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
                                    cleanupMessage = "✅ \(result.success)件をクリアしました"
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
            cleanupMessage = "✅ \(result.success)件を\(action.rawValue)しました"
            if result.failed > 0 {
                cleanupMessage! += " (❌ \(result.failed)件失敗)"
            }
            Task {
                await analyzer.scan()
                analyzer.storageInfo = analyzer.getStorageInfo()
            }
        } else {
            cleanupMessage = "❌ 操作に失敗しました"
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        if isExpanded && !subItemsLoaded {
                            item.subItems = analyzer.getSubItems(for: item)
                            subItemsLoaded = true
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
                    Text(item.category.rawValue)
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
                            Button("チェック済みをクリア") {
                                let targets = selectedOrAllSubItems()
                                guard !targets.isEmpty else { return }
                                onSubItemAction(item, targets, .delete)
                            }
                            .disabled(subItemsLoaded && item.subItems.filter(\.isSelected).isEmpty)
                        } else {
                            Button("チェック済みをゴミ箱に移動") {
                                let targets = selectedOrAllSubItems()
                                guard !targets.isEmpty else { return }
                                onSubItemAction(item, targets, .moveToTrash)
                            }
                            .disabled(subItemsLoaded && item.subItems.filter(\.isSelected).isEmpty)
                            Button("チェック済みをiCloudに退避") {
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
                        Text("ファイルがありません")
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
                                    Text("\(selectedSubs.count)件 選択中")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if item.category == .cache || item.category == .log {
                                        Button {
                                            onSubItemAction(item, selectedSubs, .delete)
                                        } label: {
                                            Text("クリア")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .controlSize(.small)
                                    } else {
                                        Button {
                                            onSubItemAction(item, selectedSubs, .moveToTrash)
                                        } label: {
                                            Text("ゴミ箱へ")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .controlSize(.small)

                                        Button {
                                            onSubItemAction(item, selectedSubs, .moveToICloud)
                                        } label: {
                                            Text("iCloud")
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
                        Text("推奨")
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
                Text("バッテリー").tag(0)
                Text("アプリ管理").tag(1)
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
                            Text("バッテリーヘルス")
                                .font(.headline)
                            Spacer()
                            Text(batteryMonitor.condition)
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
                                Text("健康度")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 80, height: 80)
                    }
                    .padding()
                    
                    // Battery details grid
                    VStack(spacing: 6) {
                        batteryRow("充電状態", batteryMonitor.isCharging ? "充電中" : "バッテリー使用中", 
                                   icon: batteryMonitor.isCharging ? "bolt.fill" : "battery.100")
                        batteryRow("バッテリー残量", "\(batteryMonitor.batteryLevel)%", icon: "battery.75")
                        batteryRow("充電サイクル", "\(batteryMonitor.cycleCount)回", icon: "arrow.triangle.2.circlepath")
                        batteryRow("最大容量", "\(batteryMonitor.maxCapacity) mAh", icon: "bolt.batteryblock")
                        batteryRow("設計容量", "\(batteryMonitor.designCapacity) mAh", icon: "square.and.pencil")
                        if batteryMonitor.temperature > 0 {
                            batteryRow("温度", String(format: "%.1f°C", batteryMonitor.temperature), icon: "thermometer.medium")
                        }
                        if !batteryMonitor.timeRemaining.isEmpty {
                            batteryRow("残り時間", batteryMonitor.timeRemaining, icon: "clock")
                        }
                    }
                    .padding(.horizontal)
                    
                    // Battery tips
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("バッテリーのコツ")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(batteryMonitor.cycleCount > 800 
                            ? "充電サイクルが800回を超えています。バッテリー交換を検討してください。" 
                            : "20%～80%の範囲で使うとバッテリー寿命が延びます。")
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
                        Text("バッテリー非搭載")
                            .font(.headline)
                        Text("このMacにはバッテリーが搭載されていません")
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
        switch batteryMonitor.condition {
        case "正常", "良好": return .green
        case "警告": return .orange
        default: return .red
        }
    }
    
    // MARK: - App Uninstaller
    private var uninstallerSection: some View {
        VStack(spacing: 0) {
            if uninstaller.isScanning {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
                    ProgressView()
                    Text("アプリをスキャン中...")
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
                    Text("アプリ管理")
                        .font(.headline)
                    Text("インストール済みアプリと残留ファイルを検出")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        Task { await uninstaller.scanInstalledApps() }
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("スキャン開始")
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
                        Text("\(uninstaller.apps.count)個のアプリ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        let totalLeftover = uninstaller.apps.reduce(0.0) { $0 + $1.leftoverSizeMB }
                        if totalLeftover > 0 {
                            Text("残留ファイル: \(formatSize(totalLeftover))")
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
                                Text("残留: " + formatSize(app.leftoverSizeMB))
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }
                            Text("合計: " + formatSize(app.totalSizeMB))
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
                    Text("「残留ファイル」＝このアプリが残した設定・キャッシュ・ログなどの補助データです。アプリを消しても残りがちで、少しずつ容量を圧迫します。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !app.leftovers.isEmpty {
                        Text("残留ファイル（\(app.leftovers.count)件 / \(formatSize(app.leftoverSizeMB))） — 項目ごとに種類・リスクが違います。残すものはチェックを外してください")
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
                                            Text("リスク\(item.risk.rawValue)")
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
                                        title: "残留削除",
                                        tint: .orange,
                                        risk: "リスク低",
                                        desc: "アプリ本体は残し、残留ファイルだけをゴミ箱へ。アプリは引き続き使えます。",
                                        action: { pendingAction = .leftoversOnly }
                                    )
                                }
                                actionChoice(
                                    title: "アンインストール",
                                    tint: .red,
                                    risk: "リスク中",
                                    desc: "アプリ本体＋残留ファイルをまとめてゴミ箱へ。このアプリは使えなくなります（再び使うには再インストールが必要）。",
                                    action: { pendingAction = .uninstall }
                                )
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Pro機能")
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
                Text(isUninstall ? "アンインストールしますか？" : "残留ファイルを削除しますか？")
                    .font(.system(size: 11, weight: .bold))
            }
            Text(isUninstall
                ? "「\(app.name)」の本体と残留ファイルをゴミ箱へ移動します。アプリは使えなくなります（再び使うには再インストールが必要）。"
                : "選択した残留 \(selectedLeftoverPaths.count)件 をゴミ箱へ移動します。アプリ本体は残り、引き続き使えます。チェックを外した項目は削除しません。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("いずれもゴミ箱へ移動するだけなので、ゴミ箱を空にするまでは元に戻せます。")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("キャンセル") { pendingAction = nil }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button(isUninstall ? "アンインストールする" : "残留を削除する") {
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
            resultMessage = "残留ファイル \(result.removedCount)件をゴミ箱へ移動（約\(formatSize(result.freedMB))）"
                + (result.errors.isEmpty ? "" : "／一部失敗 \(result.errors.count)件")
        case .uninstall:
            // チェックを外した残留は削除しない（leftoversOnly と同じ選択集合を渡す）
            let result = uninstaller.uninstallApp(app, leftoverPaths: selectedLeftoverPaths)
            resultMessage = result.errors.isEmpty
                ? "「\(app.name)」をゴミ箱へ移動しました（\(result.removedCount)項目・約\(formatSize(result.freedMB))）"
                : "一部失敗しました（成功 \(result.removedCount)項目／エラー \(result.errors.count)件）"
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
