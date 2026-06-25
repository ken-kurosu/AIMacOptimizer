import Foundation
import Darwin

/// Monitors system processes and memory usage using libproc and sysctl
final class ProcessMonitor: ObservableObject {
    @Published var systemMemory = SystemMemoryInfo(
        totalMB: 0, usedMB: 0, freeMB: 0, compressedMB: 0, swapUsedMB: 0
    )
    @Published var processes: [ProcessMemoryInfo] = []
    @Published var topProcesses: [ProcessMemoryInfo] = []

    private var timer: Timer?
    private let updateInterval: TimeInterval = 2.0

    /// Known system processes that should not be terminated
    private let systemProcessNames: Set<String> = [
        "kernel_task", "WindowServer", "loginwindow", "Finder",
        "Dock", "SystemUIServer", "mds", "mds_stores",
        "corespotlightd", "launchd", "cfprefsd", "distnoted",
        "trustd", "securityd", "opendirectoryd", "powerd",
        "coreduetd", "thermalmonitord", "syslogd"
    ]

    // MARK: - Lifecycle

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Data Collection

    func refresh() {
        Task { @MainActor in
            self.systemMemory = getSystemMemory()
            self.processes = getAllProcesses()
            self.topProcesses = aggregateByApp(processes).prefix(10).map { $0 }
        }
    }

    /// Get system-wide memory statistics using host_statistics64
    private func getSystemMemory() -> SystemMemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return SystemMemoryInfo(totalMB: 0, usedMB: 0, freeMB: 0, compressedMB: 0, swapUsedMB: 0)
        }

        let pageSize = Double(vm_kernel_page_size)
        let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024

        let activeMB = Double(stats.active_count) * pageSize / 1024 / 1024
        let wiredMB = Double(stats.wire_count) * pageSize / 1024 / 1024
        let compressedMB = Double(stats.compressor_page_count) * pageSize / 1024 / 1024

        let usedMB = activeMB + wiredMB + compressedMB

        // Get swap info via sysctl
        let swapMB = getSwapUsage()

        return SystemMemoryInfo(
            totalMB: totalMB,
            usedMB: usedMB,
            freeMB: totalMB - usedMB,
            compressedMB: compressedMB,
            swapUsedMB: swapMB
        )
    }

    /// Get swap usage via sysctl
    private func getSwapUsage() -> Double {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Double(swapUsage.xsu_used) / 1024 / 1024
    }

    /// Get all running processes with their memory usage using libproc
    private func getAllProcesses() -> [ProcessMemoryInfo] {
        // Get number of processes
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }

        // Get all PIDs
        var pids = [pid_t](repeating: 0, count: Int(bufferSize))
        let actualSize = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actualSize > 0 else { return [] }

        let pidCount = Int(actualSize)
        var results: [ProcessMemoryInfo] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // Get process info
            var taskInfo = proc_taskinfo()
            let taskInfoSize = MemoryLayout<proc_taskinfo>.size
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(taskInfoSize))
            guard ret == taskInfoSize else { continue }

            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
            proc_pidpath(pid, &nameBuffer, UInt32(nameBuffer.count))
            let fullPath = String(cString: nameBuffer)
            let name = (fullPath as NSString).lastPathComponent

            guard !name.isEmpty else { continue }

            let memoryMB = Double(taskInfo.pti_resident_size) / 1024 / 1024
            guard memoryMB > 1 else { continue } // Skip tiny processes

            let isSystem = systemProcessNames.contains(name)
            let bundleID = getBundleIdentifier(fromPath: fullPath)

            results.append(ProcessMemoryInfo(
                id: pid,
                name: name,
                memoryMB: memoryMB,
                isSystemProcess: isSystem,
                bundleIdentifier: bundleID
            ))
        }

        return results.sorted(by: >)
    }

    /// Aggregate process memory by application name
    private func aggregateByApp(_ processes: [ProcessMemoryInfo]) -> [ProcessMemoryInfo] {
        var appMemory: [String: (memoryMB: Double, pid: pid_t, isSystem: Bool, bundleID: String?)] = [:]

        for proc in processes {
            // Group Chrome Helper processes under "Google Chrome"
            let appName = normalizeAppName(proc.name)

            if let existing = appMemory[appName] {
                appMemory[appName] = (
                    memoryMB: existing.memoryMB + proc.memoryMB,
                    pid: existing.pid,
                    isSystem: proc.isSystemProcess,
                    bundleID: proc.bundleIdentifier ?? existing.bundleID
                )
            } else {
                appMemory[appName] = (proc.memoryMB, proc.id, proc.isSystemProcess, proc.bundleIdentifier)
            }
        }

        return appMemory.map { name, info in
            ProcessMemoryInfo(
                id: info.pid,
                name: name,
                memoryMB: info.memoryMB,
                isSystemProcess: info.isSystem,
                bundleIdentifier: info.bundleID
            )
        }.sorted(by: >)
    }

    /// Normalize process names to group related processes
    private func normalizeAppName(_ name: String) -> String {
        if name.contains("Google Chrome") { return "Google Chrome" }
        if name.contains("Cursor") { return "Cursor" }
        if name.contains("Claude") { return "Claude" }
        if name.contains("Slack") { return "Slack" }
        if name.contains("Adobe") { return "Adobe Creative Cloud" }
        if name.contains("Electron") { return name }
        if name.contains("Safari") { return "Safari" }
        if name.contains("Firefox") { return "Firefox" }
        return name
    }

    /// Extract bundle identifier from application path
    private func getBundleIdentifier(fromPath path: String) -> String? {
        guard path.contains("/Applications/") || path.contains(".app/") else { return nil }
        // Extract .app path
        if let range = path.range(of: ".app") {
            let appPath = String(path[...range.upperBound])
            let bundle = Bundle(path: String(appPath.dropLast(1) + "app"))
            return bundle?.bundleIdentifier
        }
        return nil
    }
}
