import SwiftUI
import AppKit
import Combine

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

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
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

        // Request notification permissions
        NotificationService.shared.requestPermission()
        
        // Start periodic notification checks (every 60 seconds)
        startNotificationTimer()
        
        print("=== AI Mac Optimizer started ===")
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

        self.panel = newPanel
    }

    // MARK: - Notification Timer
    private var notificationTimer: Timer?
    
    private func startNotificationTimer() {
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let memPercent = self.monitor.systemMemory.usagePercent
            let storage = StorageAnalyzer().getStorageInfo()
            NotificationService.shared.checkAndNotify(memoryPercent: memPercent, diskFreeGB: storage.freeGB)
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
