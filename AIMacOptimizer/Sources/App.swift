import SwiftUI
import AppKit
import Combine
import ServiceManagement
import UserNotifications

// MARK: - App Entry Point

@main
struct AIMacOptimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scenes — everything is managed by AppDelegate
        // (MenuBarExtra can't keep popover open during system dialogs,
        //  so we use our own NSStatusItem + NSPanel instead)
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Custom Panel that stays open during system dialogs

final class PersistentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Prevent the panel from closing when app deactivates (e.g. permission dialogs)
    override func resignKey() {
        super.resignKey()
        // Don't hide — stay visible
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    let monitor = ProcessMonitor()

    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var panel: PersistentPanel?
    private var hostingView: NSHostingView<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start monitoring
        monitor.startMonitoring()

        // Add Edit menu for ⌘C/⌘V/⌘X/⌘A in text fields
        setupEditMenu()

        // Create menu bar status item
        setupStatusItem()

        // 常駐アプリは常に「起動中」扱いのため、デリゲートで willPresent を実装しないと
        // 閾値通知などがバナー表示されず抑制される。ここでデリゲートを設定する。
        UNUserNotificationCenter.current().delegate = self

        // スケジュール自動最適化を初期化（保存設定が有効なら定期実行を開始）
        _ = ScheduleManager.shared

        // Start periodic notification checks (every 60 seconds)
        startNotificationTimer()

        // 初回起動はログイン項目に自動登録（既定ON）。以降はユーザー設定を尊重
        setupLaunchAtLoginDefault()

        // 初回はオンボーディングを表示（アプリをアクティブ化した状態で通知許可を要求するため、
        // メニューバー常駐アプリでも許可ダイアログが確実に前面表示される）。2回目以降は素通り。
        if UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            scheduleLaunchSummaryNotification()
            // 起動時に最新版へ自動更新（少し待ってからバックグラウンドで）
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                UpdateService.shared.checkOnLaunch()
            }
        } else {
            showOnboarding()
        }

        print("=== AI Mac Optimizer started ===")
    }

    // MARK: - オンボーディング（初回のみ）

    private var onboardingWindow: NSWindow?

    private func showOnboarding() {
        // 一時的に通常アプリ化して、ウィンドウと通知ダイアログを前面に出す
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let view = OnboardingView(
            onRequestNotifications: { completion in
                NSApp.activate(ignoringOtherApps: true)
                NotificationService.shared.requestPermission(completion: completion)
            },
            onFinish: { [weak self] in self?.finishOnboarding() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "AI Mac Optimizer"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)

        // ×ボタンで閉じても「完了」扱いにする（何度も出さない）
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            self?.completeOnboardingState()
        }

        self.onboardingWindow = win
    }

    private func finishOnboarding() {
        onboardingWindow?.close() // willClose 経由で completeOnboardingState が走る
    }

    /// 完了フラグを立て、メニューバー常駐（accessory）へ戻す。
    private func completeOnboardingState() {
        guard !UserDefaults.standard.bool(forKey: "onboardingCompleted") else { return }
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onboardingWindow = nil
        NSApp.setActivationPolicy(.accessory)
        scheduleLaunchSummaryNotification()
    }

    /// アプリ起動中でも通知をバナー＋音で表示する（常駐アプリでは必須。無いと抑制される）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Launch at Login（既定ON）

    private func setupLaunchAtLoginDefault() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "launchAtLogin") == nil {
            // 初回起動：既定でログイン時起動を有効化
            defaults.set(true, forKey: "launchAtLogin")
            try? SMAppService.mainApp.register()
        } else if defaults.bool(forKey: "launchAtLogin") {
            // 有効設定なのに未登録なら登録し直す
            if SMAppService.mainApp.status != .enabled {
                try? SMAppService.mainApp.register()
            }
        }
    }

    // MARK: - 起動サマリ通知

    private func scheduleLaunchSummaryNotification() {
        // monitor の初回計測が入るまで少し待ってから通知（メモリ値が 0 のままになるのを防ぐ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self else { return }
            guard UserDefaults.standard.object(forKey: "enableNotifications") == nil
                    || UserDefaults.standard.bool(forKey: "enableNotifications") else { return }

            let content = UNMutableNotificationContent()
            content.title = "AI Mac Optimizer 起動中"
            content.body = self.statusBody()
            content.subtitle = "タップで詳しい診断・レポートを開けます"
            content.sound = nil
            content.categoryIdentifier = "STATUS_DIGEST"
            let request = UNNotificationRequest(identifier: "launch-summary-\(Int(Date().timeIntervalSince1970))",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// メモリ/ディスクの現況を1行にまとめる（起動サマリ・毎日ステータスで共用。数値は常に無料）。
    private func statusBody() -> String {
        let mem = self.monitor.systemMemory
        let storage = StorageAnalyzer().getStorageInfo()
        var health = "良好"
        if mem.severity == .high || storage.freeGB < 10 { health = "要注意" }
        else if mem.severity == .medium || storage.usagePercent > 85 { health = "やや注意" }
        return "メモリ \(Int(mem.usagePercent))% ・ ストレージ空き \(String(format: "%.0f", storage.freeGB))GB ・ 状態: \(health)"
    }

    /// 毎日1回、現在のメモリ/ディスクの数値を通知で届ける（Free）。タップで詳しい診断/レポートへ。
    private func maybeSendDailyStatus() {
        let d = UserDefaults.standard
        guard d.object(forKey: "enableNotifications") == nil || d.bool(forKey: "enableNotifications") else { return }
        guard d.object(forKey: "dailyStatusEnabled") == nil || d.bool(forKey: "dailyStatusEnabled") else { return }
        // 24時間間隔。初回は基準日だけ置いて翌日から送る。
        if let last = d.object(forKey: "dailyStatusLastSent") as? Date {
            guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        } else {
            d.set(Date(), forKey: "dailyStatusLastSent"); return
        }
        d.set(Date(), forKey: "dailyStatusLastSent")

        let content = UNMutableNotificationContent()
        content.title = "今日のMacの状態"
        content.body = statusBody()
        content.subtitle = "タップで詳しい診断・レポートを開けます"
        content.sound = nil
        content.categoryIdentifier = "STATUS_DIGEST"
        let request = UNNotificationRequest(identifier: "daily-status-\(Int(Date().timeIntervalSince1970))",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 通知をタップした時：アプリを前面化してパネル（診断/レポート）を開く。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showPopover()
        }
        completionHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopMonitoring()
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "AI Mac Optimizer")
            button.action = #selector(togglePopover)
            button.target = self
            
            // Subscribe to memory updates
            cancellable = monitor.$systemMemory
                .receive(on: DispatchQueue.main)
                .sink { [weak self] memoryInfo in
                    self?.updateStatusItemDisplay(with: memoryInfo)
                }
        }
    }
    
    private func updateStatusItemDisplay(with memoryInfo: SystemMemoryInfo) {
        guard let button = statusItem.button else { return }
        
        // Determine color based on severity
        let textColor: NSColor = {
            switch memoryInfo.severity {
            case .low:
                return NSColor.systemGreen
            case .medium:
                return NSColor.systemOrange
            case .high:
                return NSColor.systemRed
            }
        }()
        
        // Format the percentage text
        let percentText = String(format: "%.0f%%", memoryInfo.usagePercent)
        let attributedString = NSAttributedString(
            string: percentText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: textColor
            ]
        )
        
        button.attributedTitle = attributedString
    }

    // MARK: - Popover Panel

    @objc private func togglePopover() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
            // 非表示中はプロセス列挙を止め、メニューバーの%更新のみに落として電力を抑える
            monitor.setActive(false)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        if panel == nil {
            createPanel()
        }

        guard let panel = panel, let button = statusItem.button else { return }

        // Position panel below the status item
        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 580
        let x = buttonFrame.midX - panelWidth / 2
        let y = buttonFrame.minY - panelHeight - 4

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        // 表示中はプロセス一覧を含むフル更新に切り替える（即時に一覧を出す）
        monitor.setActive(true)
    }

    private func createPanel() {
        let contentView = PopoverView(monitor: monitor)
        let hosting = NSHostingView(rootView: AnyView(contentView.frame(width: 320, height: 580)))
        self.hostingView = hosting

        let newPanel = PersistentPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isMovableByWindowBackground = false
        newPanel.contentView = hosting
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .statusBar
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false  // THIS is the key — stays open during system dialogs
        newPanel.becomesKeyOnlyIfNeeded = false
        newPanel.backgroundColor = .windowBackgroundColor

        // Close panel only when clicking the status bar icon again
        // (Don't use global mouse monitor — it closes the panel during system dialogs)

        // ×ボタンや⌘Wで閉じられた場合も省電力モード(プロセス列挙停止)へ落とす。
        // （togglePopover の orderOut 経路以外で閉じても2秒フル列挙が残らないように）
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: newPanel, queue: .main
        ) { [weak self] _ in
            self?.monitor.setActive(false)
        }

        self.panel = newPanel
    }

    // MARK: - Notification Timer
    private var notificationTimer: Timer?
    
    private func startNotificationTimer() {
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let mem = self.monitor.systemMemory
            let memPercent = mem.usagePercent
            let storage = StorageAnalyzer().getStorageInfo()
            NotificationService.shared.checkAndNotify(memoryPercent: memPercent, diskFreeGB: storage.freeGB)
            // ストレージ圧迫を監視し、圧迫時は安全なキャッシュ/ログの削除を提案/自動実行
            Task { @MainActor in DiskGuard.shared.evaluate() }

            // 毎日1回、メモリ/ディスクの数値を通知（Free・24時間未満なら即return で無コスト）
            self.maybeSendDailyStatus()

            // 週次の最適化レポート（7日経過時のみ生成・通知。それ以外は即return で無コスト）
            Task { @MainActor in WeeklyReportService.shared.checkAndSendIfDue() }

            // 月額購読のオンライン再検証（12時間に1回だけ実行・URL未設定なら無コスト）
            Task { @MainActor in await LicenseManager.shared.refreshSubscriptionValidationIfNeeded() }

            // 自動アップデート確認（6時間に1回だけ・自動OFFなら無コスト）
            UpdateService.shared.autoCheckIfDue()

            // スケジュール自動最適化が有効なときだけ、学習用にプロセスを軽く記録する
            // （パネル非表示中でも学習を進める。無効なら取得コストは発生しない）
            if ScheduleManager.shared.schedule.enabled {
                ScheduleManager.shared.recordLearningSnapshot()
            }

            // 健康状態の推移を記録（10分間隔・軽量。ここに相乗りして追加コストをほぼ0に）
            var loads = [Double](repeating: 0, count: 3)
            getloadavg(&loads, 3)
            let diskFreePct = storage.totalGB > 0 ? storage.freeGB / storage.totalGB * 100 : 0
            Task { @MainActor in
                HealthHistory.shared.record(
                    memUsedPercent: memPercent,
                    swapMB: mem.swapUsedMB,
                    diskFreePercent: diskFreePct,
                    loadAvg1: loads[0]
                )
            }
        }
    }
    
    // MARK: - Edit Menu

    private func setupEditMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        NSApp.mainMenu = mainMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
    }
}
