import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    
    private let defaults = UserDefaults.standard
    private let lastNotificationTimestamps = NSMutableDictionary()
    private let notificationCooldownInterval: TimeInterval = 30 * 60 // 30 minutes
    
    // UserDefaults keys
    private let enableNotificationsKey = "enableNotifications"
    private let notifyThresholdKey = "notifyThreshold"
    private let lastMemoryAlertKey = "lastMemoryAlertTimestamp"
    private let lastDiskAlertKey = "lastDiskAlertTimestamp"
    
    private init() {
        setupDefaults()
    }
    
    // MARK: - Setup
    
    private func setupDefaults() {
        if defaults.object(forKey: enableNotificationsKey) == nil {
            defaults.set(true, forKey: enableNotificationsKey)
        }
        if defaults.object(forKey: notifyThresholdKey) == nil {
            defaults.set(80, forKey: notifyThresholdKey)
        }
    }
    
    // MARK: - Public Methods
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
                return
            }
            if granted {
                print("Notification permissions granted")
            } else {
                print("Notification permissions denied")
            }
        }
    }

    /// 現在の通知許可状態を取得（設定画面で「なぜ通知が来ないか」を可視化するため）
    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    /// テスト通知を送る。未要求なら先に許可要求する。
    /// これが表示されれば「権限OK・配信経路OK」、出なければ権限が原因と切り分けできる。
    func sendTestNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.requestPermission()
            }
            let content = UNMutableNotificationContent()
            content.title = "AI Mac Optimizer"
            content.body = "テスト通知です。これが表示されれば通知は正常に届きます。"
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Test notification failed: \(error.localizedDescription)") }
            }
        }
    }
    
    /// 定期最適化レポートを通知する。閾値通知とは別枠（クールダウン非対象）。
    func sendReport(title: String, body: String, subtitle: String) {
        guard defaults.bool(forKey: enableNotificationsKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Report notification failed: \(error.localizedDescription)") }
        }
    }

    func checkAndNotify(memoryPercent: Double, diskFreeGB: Double) {
        let notificationsEnabled = defaults.bool(forKey: enableNotificationsKey)
        guard notificationsEnabled else { return }
        
        let threshold = defaults.double(forKey: notifyThresholdKey)
        let actualThreshold = threshold > 0 ? threshold : 80
        
        checkMemoryAlert(memoryPercent: memoryPercent, threshold: actualThreshold)
        checkDiskAlert(diskFreeGB: diskFreeGB)
    }
    
    // MARK: - Private Methods
    
    private func checkMemoryAlert(memoryPercent: Double, threshold: Double) {
        guard memoryPercent >= threshold else { return }
        
        if shouldSendNotification(type: "memory") {
            let title = L10n.notifyMemoryTitle
            let body = L10n.notifyMemoryBody(percent: Int(memoryPercent))
            let suggestion = L10n.notifyMemorySuggestion
            
            sendNotification(title: title, body: body, suggestion: suggestion)
            updateNotificationTimestamp(type: "memory")
        }
    }
    
    private func checkDiskAlert(diskFreeGB: Double) {
        let freeSpaceThreshold: Double = 10.0 // GB
        guard diskFreeGB < freeSpaceThreshold else { return }
        
        if shouldSendNotification(type: "disk") {
            let title = L10n.notifyDiskTitle
            let body = L10n.notifyDiskBody(freeGB: String(format: "%.1f", diskFreeGB))
            let suggestion = L10n.notifyDiskSuggestion
            
            sendNotification(title: title, body: body, suggestion: suggestion)
            updateNotificationTimestamp(type: "disk")
        }
    }
    
    private func shouldSendNotification(type: String) -> Bool {
        let key = type == "memory" ? lastMemoryAlertKey : lastDiskAlertKey
        guard let lastTimestamp = defaults.object(forKey: key) as? TimeInterval else {
            return true
        }
        
        let timeSinceLastNotification = Date().timeIntervalSince1970 - lastTimestamp
        return timeSinceLastNotification >= notificationCooldownInterval
    }
    
    private func updateNotificationTimestamp(type: String) {
        let key = type == "memory" ? lastMemoryAlertKey : lastDiskAlertKey
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }
    
    private func sendNotification(title: String, body: String, suggestion: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: 1)
        
        // Add subtitle with the suggestion
        content.subtitle = suggestion
        
        // Create a unique identifier for this notification
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            } else {
                print("Notification sent: \(title)")
            }
        }
    }
}
