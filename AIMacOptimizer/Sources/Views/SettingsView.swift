import SwiftUI
import ServiceManagement
import UserNotifications

/// Settings window for the app
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("autoOptimizeThreshold") private var autoOptimizeThreshold: Double = 90
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("notifyThreshold") private var notifyThreshold: Double = 80
    @AppStorage("weeklyReportEnabled") private var weeklyReportEnabled = true
    @AppStorage("dailyStatusEnabled") private var dailyStatusEnabled = true
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @StateObject private var license = LicenseManager.shared
    @ObservedObject private var diskGuard = DiskGuard.shared
    @ObservedObject private var updateService = UpdateService.shared
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled = true
    @ObservedObject private var nav = SettingsNavigation.shared
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @State private var notifyAuthStatus: UNAuthorizationStatus = .notDetermined

    /// 設定タブの定義（左サイドバーに常時表示）
    private struct SettingsTab: Identifiable {
        let id: Int
        let title: String
        let icon: String
    }

    private var settingsTabs: [SettingsTab] {
        [
            .init(id: 0, title: L10n.general, icon: "gear"),
            .init(id: 1, title: L10n.license, icon: "crown"),
            .init(id: 2, title: L10n.monitoring, icon: "gauge.medium"),
            .init(id: 3, title: L10n.autoOptimization, icon: "clock.arrow.2.circlepath"),
            .init(id: 5, title: L10n.notifications, icon: "bell"),
            .init(id: 6, title: L10n.about, icon: "info.circle"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左サイドバー（グローバルメニューを常時表示）
            VStack(alignment: .leading, spacing: 2) {
                ForEach(settingsTabs) { tab in
                    Button(action: { nav.selectedTab = tab.id }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13))
                                .frame(width: 18)
                            Text(tab.title)
                                .font(.system(size: 12, weight: nav.selectedTab == tab.id ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(nav.selectedTab == tab.id ? Color.blue.opacity(0.15) : Color.clear)
                        .foregroundColor(nav.selectedTab == tab.id ? .blue : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 160)
            .padding(8)
            .background(Color.gray.opacity(0.06))

            Divider()

            // 右コンテンツ
            ScrollView {
                settingsContent
                    .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 420)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch nav.selectedTab {
        case 0: generalTab
        case 1: licenseTab
        case 2: monitoringTab
        case 3: scheduleTab
        case 5: notificationTab
        default: aboutTab
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text(L10n.startupSettings)
            }

            Section {
                HStack {
                    Text(L10n.refreshInterval)
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text(L10n.seconds(1)).tag(1.0)
                        Text(L10n.seconds(2)).tag(2.0)
                        Text(L10n.seconds(5)).tag(5.0)
                        Text(L10n.seconds(10)).tag(10.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            } header: {
                Text(L10n.performance)
            }

            Section {
                Picker(L10n.language, selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .onChange(of: appLanguageRaw) { newValue in
                    if let lang = AppLanguage(rawValue: newValue) {
                        L10n.current = lang
                    }
                }

            } header: {
                Text(L10n.language)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - License Tab

    private var licenseTab: some View {
        Form {
            // Current plan display
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if license.currentTier.isPro {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.orange)
                            }
                            Text(L10n.currentPlan)
                                .font(.body)
                        }
                        Text(license.currentTier.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(license.currentTier.isPro ? .orange : .secondary)
                    }
                    Spacer()
                }

                if !license.currentTier.isPro {
                    // Feature comparison（実態に一致: Pro=ストレージ削除＋スケジュールのみ、他は無料）
                    VStack(alignment: .leading, spacing: 6) {
                        featureRow(L10n.featureMemoryOptimize, available: true)
                        featureRow(L10n.featureDiagnosisAI, available: true)
                        featureRow(L10n.featureStorageScan, available: true)
                        featureRow(L10n.featureMultiLang, available: true)
                        Divider()
                        featureRow(L10n.featureStorageDelete, available: false)
                        featureRow(L10n.featureScheduleOptimize, available: false)
                        featureRow(L10n.featurePrioritySupport, available: false)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(L10n.planInfo)
            }

            // Promo code section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.havePromoCode)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField(L10n.enterPromoCode, text: $license.promoCodeInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button(L10n.apply) {
                            license.activatePromoCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(license.promoCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !license.promoCodeMessage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: license.promoCodeSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(license.promoCodeSuccess ? .green : .red)
                            Text(license.promoCodeMessage)
                                .font(.caption)
                                .foregroundColor(license.promoCodeSuccess ? .green : .red)
                        }
                    }
                }
            } header: {
                Text(L10n.promoCode)
            }

            // Upgrade options (for free users)
            if !license.currentTier.isPro {
                Section {
                    VStack(spacing: 12) {
                        // Pro Monthly
                        Button(action: { license.purchaseProMonthly() }) {
                            upgradeOptionCard(
                                title: L10n.proMonthly,
                                price: PurchaseConfig.proMonthlyPrice,
                                subtitle: L10n.proMonthlySubtitle,
                                highlight: false
                            )
                        }
                        .buttonStyle(.plain)

                        // Pro Lifetime
                        Button(action: { license.purchaseProLifetime() }) {
                            upgradeOptionCard(
                                title: L10n.proLifetime,
                                price: PurchaseConfig.proLifetimePrice,
                                subtitle: L10n.proLifetimeSubtitle,
                                highlight: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L10n.enterLicenseKeyHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } header: {
                    Text(L10n.upgradeSection)
                }

                // License Key section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.enterLicenseKey)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("AIMAC-XXXX-XXXX-XXXX", text: $license.licenseKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button(L10n.apply) {
                                license.activateLicenseKey()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(license.licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !license.licenseKeyMessage.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: license.licenseKeySuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(license.licenseKeySuccess ? .green : .red)
                                Text(license.licenseKeyMessage)
                                    .font(.caption)
                                    .foregroundColor(license.licenseKeySuccess ? .green : .red)
                            }
                        }
                    }
                } header: {
                    Text(L10n.licenseKey)
                }
            }

            // Usage stats
            Section {
                HStack {
                    Text(L10n.weeklyAISuggestionUse)
                    Spacer()
                    Text("\(license.weeklyAISuggestionsUsed) / \(license.currentTier.isPro ? "∞" : "3")")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if license.currentTier.isPro {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(L10n.resetLicense, role: .destructive) {
                            license.resetLicense()
                        }
                        Text(L10n.resetLicenseNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(L10n.usageStatus)
            }

            // 解約（課金停止）はStripe側で行う。「このMacのライセンスを解除」との混同を防ぐため別セクションで明示。
            if license.currentTier.isPro {
                Section {
                    Text(L10n.cancelPlanNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let urlStr = PurchaseConfig.manageSubscriptionURL, let url = URL(string: urlStr) {
                        Link("解約ページを開く（Stripe）", destination: url)
                    }
                } header: {
                    Text(L10n.cancelPlanTitle)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func featureRow(_ text: String, available: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: available ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 11))
                .foregroundColor(available ? .green : .gray)
            Text(text)
                .font(.caption)
                .foregroundColor(available ? .primary : .secondary)
        }
    }

    private func upgradeOptionCard(title: String, price: String, subtitle: String, highlight: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if highlight {
                        Text(L10n.recommendedBadge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(price)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(highlight ? .blue : .primary)
        }
        .padding(10)
        .background(highlight ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(highlight ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Monitoring Tab

    private var monitoringTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.autoOptimizeThreshold)
                        Spacer()
                        Text("\(Int(autoOptimizeThreshold))%")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $autoOptimizeThreshold, in: 70...95, step: 5)

                    Text(L10n.autoOptimizeThresholdDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(L10n.memoryMonitoring)
            }

            Section {
                Toggle(L10n.monitorStoragePressure, isOn: $diskGuard.settings.enabled)

                if diskGuard.settings.enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.pressureUsagePercent)
                            Spacer()
                            Text("\(Int(diskGuard.settings.thresholdPercent))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $diskGuard.settings.thresholdPercent, in: 80...95, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.pressureFreeSpace)
                            Spacer()
                            Text(L10n.lessThanGB(Int(diskGuard.settings.minFreeGB)))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $diskGuard.settings.minFreeGB, in: 5...50, step: 1)
                    }

                    Text(L10n.pressureRuleDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(L10n.autoFreeOnPressure, isOn: $diskGuard.settings.autoClean)

                    Text(diskGuard.settings.autoClean
                        ? L10n.autoFreeOnDesc
                        : L10n.autoFreeOffDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("空きが約\(Int(diskGuard.settings.emergencyFreeGB))GB未満になると「緊急」として強く通知し、安全に消せる項目の一覧とワンボタンをすぐ出します。削除は勝手に行わず、必ず承認を取ります（上の自動削除をONにした場合のみ、その同意に基づき自動実行）。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(L10n.storageAutoGuard)
            }

            Section {
                Text(L10n.browserAutomationNote)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(L10n.openAutomationSettings) {
                    openAutomationPreferences()
                }
            } header: {
                Text(L10n.browserIntegration)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Schedule Tab

    private var scheduleTab: some View {
        Form {
            Section {
                if license.canUseSchedule {
                    Toggle(L10n.scheduleEnabled, isOn: Binding(
                        get: { scheduleManager.schedule.enabled },
                        set: { scheduleManager.enableSchedule($0) }
                    ))

                    if scheduleManager.schedule.enabled {
                        Picker(L10n.runInterval, selection: Binding(
                            get: { scheduleManager.schedule.intervalMinutes },
                            set: { scheduleManager.updateInterval($0) }
                        )) {
                            Text(L10n.minutes(30)).tag(30)
                            Text(L10n.hours(1)).tag(60)
                            Text(L10n.hours(2)).tag(120)
                            Text(L10n.hours(4)).tag(240)
                        }

                        Toggle(L10n.onlyWhenIdle, isOn: Binding(
                            get: { scheduleManager.schedule.onlyWhenIdle },
                            set: { scheduleManager.setOnlyWhenIdle($0) }
                        ))

                        if let next = scheduleManager.nextAutoRun {
                            Text(L10n.nextRun(next.formatted(date: .omitted, time: .shortened)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.aboutSafety)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(L10n.scheduleSafetyDesc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Pro lock for schedule
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text(L10n.scheduleProLock)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(L10n.scheduleProLockDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(L10n.checkOnLicenseTab) {
                            nav.selectedTab = 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } header: {
                Text(L10n.autoOptimization)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.aiLearningData)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(L10n.aiLearningDataDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(L10n.resetLearningData, role: .destructive) {
                    PatternLearner.shared.resetLearning()
                }
            } header: {
                Text(L10n.aiLearning)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notification Tab

    private var notificationTab: some View {
        Form {
            Section {
                Toggle(L10n.enableNotifications, isOn: $enableNotifications)

                if enableNotifications {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.notifyThreshold)
                            Spacer()
                            Text("\(Int(notifyThreshold))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $notifyThreshold, in: 60...95, step: 5)

                        Text(L10n.notifyThresholdDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(L10n.notificationSettings)
            }

            // 毎日のステータス通知（数値は無料）＋ 週次の詳しいレポート
            Section {
                Toggle("毎日のステータス通知", isOn: $dailyStatusEnabled)
                Text("1日1回、現在のメモリ使用率とストレージ空き容量を通知でお届けします（無料）。通知をタップすると詳しい診断・レポートを開けます。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("週次の最適化レポート", isOn: $weeklyReportEnabled)
                Text("何が容量を食っているか・空き容量やSwapの推移・快適に使うための助言を、週に1回まとめて通知します。実測値と履歴だけを根拠にし、誇張はしません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("今すぐレポートを確認") {
                    Task { await WeeklyReportService.shared.generateNow() }
                }
            } header: {
                Text("定期レポート")
            }

            // 通知が来ない原因（多くは権限未許可）を可視化・解消する
            Section {
                HStack {
                    Text("通知の許可状態")
                    Spacer()
                    Text(authStatusText)
                        .foregroundColor(authStatusColor)
                        .fontWeight(.medium)
                }

                if notifyAuthStatus == .denied {
                    Text("macOSの通知が「許可しない」になっています。閾値を超えても通知は届きません。下のボタンからシステム設定で許可してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("テスト通知を送る") {
                    NotificationService.shared.sendTestNotification()
                    // 送信直後に状態を取り直す（初回は許可ダイアログが出る）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshNotifyAuthStatus() }
                }

                Button("システムの通知設定を開く") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("通知が来ない時")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshNotifyAuthStatus() }
    }

    private var authStatusText: String {
        switch notifyAuthStatus {
        case .authorized, .provisional, .ephemeral: return "許可されています"
        case .denied: return "許可されていません"
        case .notDetermined: return "未設定（テスト通知で許可を求めます）"
        @unknown default: return "不明"
        }
    }

    private var authStatusColor: Color {
        switch notifyAuthStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .orange
        }
    }

    private func refreshNotifyAuthStatus() {
        NotificationService.shared.authorizationStatus { status in
            notifyAuthStatus = status
        }
    }

    // AI設定はチャット画面側に一本化したため、設定タブからは削除（プロバイダ切替・APIキーはチャットで完結）

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "memorychip")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("AI Mac Optimizer")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 4) {
                Text(L10n.appVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if license.currentTier.isPro {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 2) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(license.currentTier.displayName)
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }

            Text(L10n.aboutDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()

            // 自動アップデート（App Store 外配布のため独自アップデーター）
            VStack(spacing: 8) {
                Toggle("自動アップデート", isOn: $autoUpdateEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: autoUpdateEnabled) { newValue in
                        UpdateService.shared.autoUpdateEnabled = newValue
                    }
                HStack(spacing: 10) {
                    Button {
                        Task { await updateService.check(userInitiated: true) }
                    } label: {
                        if updateService.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("アップデートを確認")
                        }
                    }
                    .disabled(updateService.isBusy)
                    Button("リリースページ") { updateService.openReleasesPage() }
                        .buttonStyle(.link)
                }
                if !updateService.statusMessage.isEmpty {
                    Text(updateService.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("新しいバージョンを自動でダウンロードして更新します（配布は公証済み）。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Divider()

            // 不具合・バグ・要望の報告（環境情報を添えてメール作成）
            VStack(spacing: 6) {
                Button(action: reportBug) {
                    HStack(spacing: 6) {
                        Image(systemName: "ladybug.fill")
                        Text(L10n.reportBug)
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                Text(L10n.reportBugDesc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text("© 2026 AI Mac Optimizer")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// サポート連絡先（実際の運用に合わせて差し替え可能）
    private let supportEmail = "kurosu@i-kasa.com"

    /// 不具合報告メールを作成（環境情報を自動添付）
    private func reportBug() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let arch: String
        #if arch(arm64)
        arch = "Apple Silicon"
        #else
        arch = "Intel"
        #endif
        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0"
        let body = L10n.bugReportBody(osVersion: osVersion, arch: arch, version: appVer)
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = supportEmail
        comps.queryItems = [
            URLQueryItem(name: "subject", value: L10n.bugReportSubject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }

    private func openAutomationPreferences() {
        // Chrome/Safari のタブ操作(AppleScript)に必要なのはオートメーション権限
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }
}
