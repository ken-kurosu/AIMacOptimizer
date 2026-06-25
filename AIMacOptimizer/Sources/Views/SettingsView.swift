import SwiftUI
import ServiceManagement

/// Settings window for the app
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoOptimizeThreshold") private var autoOptimizeThreshold: Double = 90
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("notifyThreshold") private var notifyThreshold: Double = 80
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @StateObject private var license = LicenseManager.shared
    @ObservedObject private var diskGuard = DiskGuard.shared
    @State private var selectedTab = 0
    @State private var scheduleEnabled = false
    @State private var scheduleInterval = 60

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(L10n.general, systemImage: "gear") }
                .tag(0)

            licenseTab
                .tabItem { Label("ライセンス", systemImage: "crown") }
                .tag(1)

            monitoringTab
                .tabItem { Label(L10n.monitoring, systemImage: "gauge.medium") }
                .tag(2)

            scheduleTab
                .tabItem { Label(L10n.autoOptimization, systemImage: "clock.arrow.2.circlepath") }
                .tag(3)

            aiChatTab
                .tabItem { Label("AIチャット", systemImage: "bubble.left.and.bubble.right") }
                .tag(4)

            notificationTab
                .tabItem { Label(L10n.notifications, systemImage: "bell") }
                .tag(5)

            aboutTab
                .tabItem { Label(L10n.about, systemImage: "info.circle") }
                .tag(6)
        }
        .frame(width: 450, height: 400)
        .padding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("起動設定")
            }

            Section {
                HStack {
                    Text("更新間隔")
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("1秒").tag(1.0)
                        Text("2秒").tag(2.0)
                        Text("5秒").tag(5.0)
                        Text("10秒").tag(10.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            } header: {
                Text("パフォーマンス")
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

                if !license.canUseMultiLanguage && appLanguageRaw != AppLanguage.system.rawValue {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("多言語切替はPro機能です")
                            .font(.caption)
                            .foregroundColor(.orange)
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
                                    .foregroundColor(.yellow)
                            }
                            Text("現在のプラン")
                                .font(.body)
                        }
                        Text(license.currentTier.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(license.currentTier.isPro ? .yellow : .secondary)
                    }
                    Spacer()
                }

                if !license.currentTier.isPro {
                    // Feature comparison for free users
                    VStack(alignment: .leading, spacing: 6) {
                        featureRow("メモリ分析・Chrome/Safariタブ分析", available: true)
                        featureRow("ストレージスキャン（表示のみ）", available: true)
                        featureRow("AI提案（3回/週）", available: true)
                        Divider()
                        featureRow("ストレージ削除・クリーンアップ", available: false)
                        featureRow("AI提案（無制限）", available: false)
                        featureRow("AIチャット相談", available: false)
                        featureRow("スケジュール自動最適化", available: false)
                        featureRow("多言語対応", available: false)
                        featureRow("優先サポート", available: false)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("プラン情報")
            }

            // Promo code section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("プロモコードをお持ちの方はこちら")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("プロモコードを入力", text: $license.promoCodeInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("適用") {
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
                Text("プロモコード")
            }

            // Upgrade options (for free users)
            if !license.currentTier.isPro {
                Section {
                    VStack(spacing: 12) {
                        // Pro Monthly
                        Button(action: { license.purchaseProMonthly() }) {
                            upgradeOptionCard(
                                title: "Pro（月額）",
                                price: PurchaseConfig.proMonthlyPrice,
                                subtitle: "いつでもキャンセル可能",
                                highlight: false
                            )
                        }
                        .buttonStyle(.plain)

                        // Pro Lifetime
                        Button(action: { license.purchaseProLifetime() }) {
                            upgradeOptionCard(
                                title: "Pro Lifetime",
                                price: PurchaseConfig.proLifetimePrice,
                                subtitle: "買い切り・永久ライセンス",
                                highlight: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Text("購入後にメールで届くライセンスキーを下記に入力してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                } header: {
                    Text("アップグレード")
                }

                // License Key section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("購入後にメールで届くライセンスキーを入力")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("AIMAC-XXXX-XXXX-XXXX", text: $license.licenseKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("適用") {
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
                    Text("ライセンスキー")
                }
            }

            // Usage stats
            Section {
                HStack {
                    Text("今週のAI提案使用回数")
                    Spacer()
                    Text("\(license.weeklyAISuggestionsUsed) / \(license.currentTier.isPro ? "∞" : "3")")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if license.currentTier.isPro {
                    Button("ライセンスをリセット（Free に戻す）", role: .destructive) {
                        license.resetLicense()
                    }
                }
            } header: {
                Text("利用状況")
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
                        Text("おすすめ")
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
                        Text("自動最適化しきい値")
                        Spacer()
                        Text("\(Int(autoOptimizeThreshold))%")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $autoOptimizeThreshold, in: 70...95, step: 5)

                    Text("メモリ使用率がこの値を超えると、最適化の提案を自動表示します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("メモリ監視")
            }

            Section {
                Toggle("ディスク圧迫を監視する", isOn: $diskGuard.settings.enabled)

                if diskGuard.settings.enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("圧迫とみなす使用率")
                            Spacer()
                            Text("\(Int(diskGuard.settings.thresholdPercent))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $diskGuard.settings.thresholdPercent, in: 80...95, step: 1)
                    }

                    Toggle("圧迫時は自動で空ける（通知のみ）", isOn: $diskGuard.settings.autoClean)

                    Text(diskGuard.settings.autoClean
                        ? "ディスクが圧迫したら、リスクのないキャッシュ/ログを自動削除し、結果を通知でお知らせします。"
                        : "ディスクが圧迫したら、何を消すか・安全度を提示して、ワンボタンで空けられるよう提案します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("ディスク自動ガード")
            }

            Section {
                Text("Chromeタブの分析にはアクセシビリティ権限が必要です。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("アクセシビリティ設定を開く") {
                    openAccessibilityPreferences()
                }
            } header: {
                Text("Chrome連携")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Schedule Tab

    private var scheduleTab: some View {
        Form {
            Section {
                if license.canUseSchedule {
                    Toggle(L10n.scheduleEnabled, isOn: $scheduleEnabled)

                    if scheduleEnabled {
                        Picker("実行間隔", selection: $scheduleInterval) {
                            Text("30分").tag(30)
                            Text("1時間").tag(60)
                            Text("2時間").tag(120)
                            Text("4時間").tag(240)
                        }

                        Toggle("ユーザーがアイドル時のみ実行", isOn: .constant(true))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("安全性について")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("自動最適化は、過去に3回以上手動で最適化したアプリのみを対象とします。業務中のアプリは自動で終了しません。")
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
                        Text("スケジュール自動最適化はPro機能です")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Proにアップグレードすると、定期的な自動最適化を設定できます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("ライセンスタブで確認") {
                            selectedTab = 1
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
                    Text("AI学習データ")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("アプリの使用パターンを学習して、より適切な最適化提案を行います。データはローカルにのみ保存されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("学習データをリセット", role: .destructive) {
                    PatternLearner().resetLearning()
                }
            } header: {
                Text("AI学習")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notification Tab

    private var notificationTab: some View {
        Form {
            Section {
                Toggle("通知を有効にする", isOn: $enableNotifications)

                if enableNotifications {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("通知しきい値")
                            Spacer()
                            Text("\(Int(notifyThreshold))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $notifyThreshold, in: 60...95, step: 5)

                        Text("メモリ使用率がこの値を超えると通知を表示します")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("通知設定")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - AI Chat Settings Tab

    @StateObject private var chatSettingsService = AIChatService()

    private var aiChatTab: some View {
        Form {
            Section {
                Picker("AIプロバイダー", selection: $chatSettingsService.settings.provider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API キー")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("sk-...", text: $chatSettingsService.settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("モデル（空欄でデフォルト）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(chatSettingsService.settings.provider.defaultModel, text: $chatSettingsService.settings.model)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("状態")
                    Spacer()
                    if chatSettingsService.settings.isConfigured {
                        Label("設定済み", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Label("未設定", systemImage: "exclamationmark.circle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Button("保存") {
                    chatSettingsService.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("AI API設定")
            }

            Section {
                Text("推奨: OpenAI GPT-4o-mini（最安: 入力 $0.15/1Mトークン）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("APIキーはお使いのMacのKeychainに安全に保存されます。外部に送信されることはありません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("AIチャットはPro機能です。診断レポートの閲覧はFreeでも利用できます。")
                    .font(.caption)
                    .foregroundColor(.orange)
            } header: {
                Text("コストについて")
            }
        }
        .formStyle(.grouped)
    }

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
                Text("バージョン 2.0.0")
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

            Text("AIがあなたのMacのメモリとストレージを賢く最適化します。\n11種類のAI分析で、使用パターンを学習してより適切な提案を行います。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()

            Text("© 2026 AI Mac Optimizer")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
