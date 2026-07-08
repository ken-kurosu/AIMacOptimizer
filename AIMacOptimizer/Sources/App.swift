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

        // Request notification permissions
        NotificationService.shared.requestPermission()

        // スケジュール自動最適化を初期化（保存設定が有効なら定期実行を開始）
        _ = ScheduleManager.shared

        // Start periodic notification checks (every 60 seconds)
        startNotificationTimer()

        // 初回起動はログイン項目に自動登録（既定ON）。以降はユーザー設定を尊重
        setupLaunchAtLoginDefault()

        // 起動時に現在の状態を軽く通知して、存在を忘れられないようにする
        scheduleLaunchSummaryNotification()

        print("=== AI Mac Optimizer started ===")
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

            let mem = self.monitor.systemMemory
            let storage = StorageAnalyzer().getStorageInfo()

            // 軽いヘルスチェック（重い Deep Diagnosis は走らせない）
            var health = "良好"
            if mem.severity == .high || storage.freeGB < 10 { health = "要注意" }
            else if mem.severity == .medium || storage.usagePercent > 85 { health = "やや注意" }

            let body = "メモリ \(Int(mem.usagePercent))% ・ ストレージ空き \(String(format: "%.0f", storage.freeGB))GB ・ 状態: \(health)"

            let content = UNMutableNotificationContent()
            content.title = "AI Mac Optimizer 起動中"
            content.body = body
            content.subtitle = "メニューバーから詳しい診断・最適化ができます"
            content.sound = nil
            let request = UNNotificationRequest(identifier: "launch-summary-\(Int(Date().timeIntervalSince1970))",
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
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

            // 週次の最適化レポート（7日経過時のみ生成・通知。それ以外は即return で無コスト）
            Task { @MainActor in WeeklyReportService.shared.checkAndSendIfDue() }

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
