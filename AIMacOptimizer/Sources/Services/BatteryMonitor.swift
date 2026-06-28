import Foundation
import Combine
import IOKit

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var isCharging: Bool = false
    @Published var batteryLevel: Int = 0
    @Published var cycleCount: Int = 0
    @Published var maxCapacity: Int = 0
    @Published var designCapacity: Int = 0
    @Published var healthPercent: Int = 0
    @Published var temperature: Double = 0.0
    @Published var condition: String = "Unknown"
    @Published var isAvailable: Bool = false
    @Published var timeRemaining: String = "Unknown"
    
    private var refreshTimer: Timer?
    
    init() {
        refresh()
        // Optional: set up timer to refresh every 60 seconds
        startRefreshTimer()
    }
    
    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Public Methods
    
    func refresh() {
        Task {
            await readBatteryInfo()
        }
    }
    
    // MARK: - Private Methods
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func readBatteryInfo() async {
        // Get the IOPMPowerSource service
        let matchDict = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        
        let kernResult = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        
        guard kernResult == KERN_SUCCESS else {
            // No battery found (likely a desktop Mac)
            await updateAvailability(false)
            return
        }
        
        defer { IOObjectRelease(iterator) }
        
        let battery = IOIteratorNext(iterator)
        guard battery != MACH_PORT_NULL else {
            await updateAvailability(false)
            return
        }
        
        defer { IOObjectRelease(battery) }
        
        // Battery found
        await updateAvailability(true)
        
        // Read battery properties
        var properties: Unmanaged<CFMutableDictionary>?
        let propertiesResult = IORegistryEntryCreateCFProperties(battery, &properties, kCFAllocatorDefault, 0)
        
        guard propertiesResult == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] else {
            return
        }
        
        // Extract battery information
        let isCharging = (props["IsCharging"] as? NSNumber)?.boolValue ?? false
        let currentCapacity = (props["CurrentCapacity"] as? NSNumber)?.intValue ?? 0
        let maxCap = (props["MaxCapacity"] as? NSNumber)?.intValue ?? 0
        let designCap = (props["DesignCapacity"] as? NSNumber)?.intValue ?? 1 // Avoid division by zero
        // Apple Silicon では MaxCapacity/CurrentCapacity が「設計比の%」で返るため、
        // 健全度は生容量(mAh)同士で算出する。古いIntel機(mAh表記)とも両対応にする。
        let rawMaxCap = (props["AppleRawMaxCapacity"] as? NSNumber)?.intValue ?? 0
        let cycleCount = (props["CycleCount"] as? NSNumber)?.intValue ?? 0
        let tempCentiDegrees = (props["Temperature"] as? NSNumber)?.intValue ?? 0
        let timeRemaining = (props["TimeRemaining"] as? NSNumber)?.intValue ?? -1

        // Calculate values
        // バッテリー残量: CurrentCapacity が既に%（<=100）ならそのまま、mAh なら比率で算出
        let batteryLvl: Int = currentCapacity <= 100
            ? currentCapacity
            : (maxCap > 0 ? (currentCapacity * 100) / maxCap : 0)
        // 健全度（最大容量/設計容量）
        let healthPercent: Int
        if rawMaxCap > 0 && designCap > 100 {
            healthPercent = min(100, (rawMaxCap * 100) / designCap) // mAh どうし（最も正確）
        } else if maxCap <= 100 {
            healthPercent = maxCap // Apple Silicon: MaxCapacity は既に設計比の%
        } else {
            healthPercent = designCap > 0 ? min(100, (maxCap * 100) / designCap) : 0 // 旧来(mAh)
        }
        let temp = Double(tempCentiDegrees) / 100.0
        
        // Determine condition based on health
        let conditionStr = getCondition(healthPercent: healthPercent, isCharging: isCharging)
        
        // Format time remaining
        let timeStr = formatTimeRemaining(timeRemaining)
        
        // Update all published properties
        await MainActor.run {
            self.isCharging = isCharging
            self.batteryLevel = max(0, min(100, batteryLvl))
            self.cycleCount = cycleCount
            // 「最大容量」は実 mAh を表示する。Apple Silicon では MaxCapacity が設計比%(~100)で
            // 返るため、そのまま mAh 表示すると「100 mAh / 設計 8694 mAh」と桁違いの矛盾になる。
            // 実 mAh の AppleRawMaxCapacity があればそれを使い、無い旧Intel機は mAh の maxCap を使う。
            self.maxCapacity = rawMaxCap > 0 ? rawMaxCap : maxCap
            self.designCapacity = designCap
            self.healthPercent = max(0, min(100, healthPercent))
            self.temperature = temp
            self.condition = conditionStr
            self.timeRemaining = timeStr
        }
    }
    
    private func updateAvailability(_ available: Bool) async {
        await MainActor.run {
            self.isAvailable = available
            if !available {
                // バッテリー非搭載（デスクトップMac）では以降ポーリングしても無意味なので止める
                stopRefreshTimer()
                self.batteryLevel = 0
                self.cycleCount = 0
                self.maxCapacity = 0
                self.designCapacity = 0
                self.healthPercent = 0
                self.temperature = 0.0
                self.condition = "Desktop"
                self.timeRemaining = "N/A"
            }
        }
    }
    
    private func getCondition(healthPercent: Int, isCharging: Bool) -> String {
        if healthPercent >= 100 {
            return "正常" // Normal
        } else if healthPercent >= 80 {
            return "良好" // Good
        } else if healthPercent >= 60 {
            return "警告" // Warning
        } else {
            return "交換推奨" // Replace recommended
        }
    }
    
    private func formatTimeRemaining(_ minutes: Int) -> String {
        guard minutes > 0 else { return "計算中" } // Calculating
        
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 {
            return String(format: "%d時間 %d分", hours, mins)
        } else {
            return String(format: "%d分", mins)
        }
    }
}