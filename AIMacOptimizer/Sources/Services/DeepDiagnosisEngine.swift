import Foundation
import AppKit

/// Deep Diagnosis Engine — runs 9 diagnostic checks locally (no API cost)
/// Produces a comprehensive DiagnosisReport with findings and overall health score.
@MainActor
final class DeepDiagnosisEngine: ObservableObject {
    @Published var isRunning = false
    @Published var currentStep: String = ""
    @Published var progress: Double = 0  // 0.0 – 1.0
    @Published var lastReport: DiagnosisReport?

    private let processMonitor: ProcessMonitor
    private let optimizer = MemoryOptimizer()

    init(processMonitor: ProcessMonitor) {
        self.processMonitor = processMonitor
    }

    /// Run all 9 diagnosis engines and produce a report
    func runFullDiagnosis() async -> DiagnosisReport {
        isRunning = true
        progress = 0
        var allFindings: [DiagnosisFinding] = []

        let steps: [(String, () async -> [DiagnosisFinding])] = [
            ("CPU負荷を分析中...", diagnoseCPU),
            ("メモリ状態を分析中...", diagnoseMemory),
            ("ストレージ容量を分析中...", diagnoseDisk),
            ("iCloud同期を確認中...", diagnoseICloudSync),
            ("セキュリティソフトを確認中...", diagnoseSecuritySoftware),
            ("開発ツールを確認中...", diagnoseDevTools),
            ("ブラウザ・アプリを分析中...", diagnoseBrowserApps),
            ("ログイン項目を確認中...", diagnoseLoginItems),
        ]

        for (i, step) in steps.enumerated() {
            currentStep = step.0
            let findings = await step.1()
            allFindings.append(contentsOf: findings)
            progress = Double(i + 1) / Double(steps.count + 1)
        }

        // 9. Composite score
        currentStep = "総合スコアを算出中..."
        let score = calculateOverallScore(findings: allFindings)
        progress = 1.0

        let snapshot = captureSystemSnapshot()

        let report = DiagnosisReport(
            timestamp: Date(),
            findings: allFindings,
            overallScore: score,
            systemSnapshot: snapshot
        )

        lastReport = report
        isRunning = false
        currentStep = ""
        return report
    }

    // MARK: - Auto-Fix Execution

    /// フォント関連（削除すると表示崩れの恐れ）かどうか
    private func isFontProtected(_ s: String) -> Bool {
        let l = s.lowercased()
        let tokens = ["font", "com.apple.fontregistry", "com.apple.ats", "fontvaliator", "fontd"]
        return tokens.contains { l.contains($0) }
    }

    /// Execute a fix action for a specific finding
    /// Returns a human-readable result message
    func executeFix(for finding: DiagnosisFinding) async -> String {
        switch finding.fixAction {
        case .purgeRAM:
            let success = await optimizer.purgeRAM()
            return success ? "RAMパージを実行しました。メモリが解放されます。" : "RAMパージに失敗しました。管理者権限が必要な場合があります。"

        case .quitApp:
            let appName = finding.fixTarget
            // pid があれば pid 指定で確実に終了（ヘルパー等 localizedName で引けないプロセスにも対応）
            if let pidStr = finding.rawData["pid"], let pid = Int32(pidStr) {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    let ok = app.terminate()
                    return ok ? "\(appName) を終了しました。" : "\(appName) の終了に失敗しました。手動で終了してください。"
                }
                let ok = kill(pid, SIGTERM) == 0
                return ok ? "\(appName) を終了しました。" : "\(appName) の終了に失敗しました。手動で終了してください。"
            }
            let success = optimizer.quitApp(name: appName)
            return success ? "\(appName) を終了しました。" : "\(appName) の終了に失敗しました。手動で終了してください。"

        case .clearCache:
            let path = finding.fixTarget
            // フォント関連のキャッシュディレクトリ自体は触らない（表示崩れ防止）
            if isFontProtected(path) {
                return "フォント関連のため安全のためスキップしました。"
            }
            let sizeBefore = optimizer.getDirectorySizeMB(path)
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: path) {
                for file in contents {
                    // フォント関連ファイル/サブフォルダは保護（font, FontRegistry, ATS 等）
                    if isFontProtected(file) { continue }
                    try? fm.removeItem(atPath: "\(path)/\(file)")
                }
            }
            let sizeAfter = optimizer.getDirectorySizeMB(path)
            let freed = sizeBefore - sizeAfter
            let freedStr = freed >= 1024 ? String(format: "%.1f GB", freed / 1024) : String(format: "%.0f MB", freed)
            return "キャッシュを削除しました。約 \(freedStr) 解放。"

        case .clearDerivedData:
            let path = finding.fixTarget.isEmpty
                ? "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"
                : finding.fixTarget
            let sizeBefore = optimizer.getDirectorySizeMB(path)
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: path) {
                for dir in contents {
                    try? fm.removeItem(atPath: "\(path)/\(dir)")
                }
            }
            let freed = sizeBefore - optimizer.getDirectorySizeMB(path)
            let freedStr = freed >= 1024 ? String(format: "%.1f GB", freed / 1024) : String(format: "%.0f MB", freed)
            return "DerivedDataを削除しました。約 \(freedStr) 解放。次回ビルド時に再生成されます。"

        case .clearBrowserCache:
            let caches = optimizer.getBrowserCacheInfo()
            var totalFreed: Double = 0
            for cache in caches {
                totalFreed += optimizer.clearBrowserCache(path: cache.path)
            }
            let freedStr = totalFreed >= 1024 ? String(format: "%.1f GB", totalFreed / 1024) : String(format: "%.0f MB", totalFreed)
            return "ブラウザキャッシュを削除しました。約 \(freedStr) 解放。"

        case .flushDNS:
            let success = await optimizer.flushDNSCache()
            return success ? "DNSキャッシュをフラッシュしました。" : "DNSフラッシュに失敗しました。"

        case .openSystemSettings:
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            NSWorkspace.shared.open(url)
            return "システム設定（ログイン項目）を開きました。"

        case .openFontBook:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Font Book.app"))
            return "Font Bookを開きました。「すべてのフォントを復元」を実行してください。"

        case .none:
            return "この項目には自動修復がありません。AIチャットで詳しい対処法を相談できます。"
        }
    }

    /// Execute all auto-fixable findings at once (one-click optimize from diagnosis)
    /// リスクの低い項目のみ自動実行し、高リスク項目（アプリ/プロセス終了）は個別承認用に返す。
    func executeAllFixes() async -> (fixed: Int, messages: [String], pendingRisky: [DiagnosisFinding]) {
        guard let report = lastReport else { return (0, ["診断を先に実行してください"], []) }

        let fixable = report.findings.filter { $0.isAutoFixable && $0.fixAction != .none }
        let safe = fixable.filter { !$0.fixAction.isRisky }
        let risky = fixable.filter { $0.fixAction.isRisky }

        var fixed = 0
        var messages: [String] = []
        for finding in safe {
            messages.append(await executeFix(for: finding))
            fixed += 1
        }
        if !risky.isEmpty {
            messages.append("リスクのある操作 \(risky.count) 件（アプリ/プロセスの終了）は自動実行していません。下で内容を確認し、個別に承認してください。")
        }

        // Re-run diagnosis to update score（安全な修復の反映）
        _ = await runFullDiagnosis()

        return (fixed, messages, risky)
    }

    // MARK: - 1. CPU Diagnosis

    private func diagnoseCPU() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []

        // Get load average
        let loadAvg = getLoadAverage()
        let cpuCount = ProcessInfo.processInfo.processorCount

        if let avg1 = loadAvg.first, avg1 > Double(cpuCount) * 2 {
            findings.append(DiagnosisFinding(
                category: .cpu, severity: .critical,
                title: "CPU負荷が極めて高い",
                detail: "Load Average: \(loadAvg.map { String(format: "%.1f", $0) }.joined(separator: "/")) (CPU \(cpuCount)コア)",
                suggestion: "CPUを大量消費しているプロセスを特定して対処してください。下記の高負荷プロセス一覧を確認してください。",
                rawData: ["load_avg": loadAvg.map { String(format: "%.1f", $0) }.joined(separator: ","),
                          "cpu_cores": "\(cpuCount)"]
            ))
        } else if let avg1 = loadAvg.first, avg1 > Double(cpuCount) {
            findings.append(DiagnosisFinding(
                category: .cpu, severity: .warning,
                title: "CPU負荷が高め",
                detail: "Load Average: \(loadAvg.map { String(format: "%.1f", $0) }.joined(separator: "/"))",
                suggestion: "バックグラウンドで重い処理が走っている可能性があります。",
                rawData: ["load_avg": loadAvg.map { String(format: "%.1f", $0) }.joined(separator: ",")]
            ))
        } else {
            findings.append(DiagnosisFinding(
                category: .cpu, severity: .good,
                title: "CPU負荷は正常",
                detail: "Load Average: \(loadAvg.map { String(format: "%.1f", $0) }.joined(separator: "/"))",
                suggestion: "特に対処は不要です。"
            ))
        }

        // Find high-CPU processes
        let highCPU = getHighCPUProcesses()
        for (pid, name, cpu) in highCPU {
            let exp = ProcessCatalog.explain(name: name, pid: pid)
            let suggestion = exp.quitRecommended
                ? "不要であれば終了するとCPU負荷が軽減されます。終了前に「詳細を確認」でこのプロセスが何か・終了リスクをご確認ください。"
                : "システム/重要プロセスのため終了は推奨しません。「詳細を確認」で内容と理由をご確認ください。"
            findings.append(DiagnosisFinding(
                category: .cpu, severity: cpu > 100 ? .critical : .warning,
                title: "\(name) が CPU \(String(format: "%.1f", cpu))% 使用",
                detail: "このプロセスがCPUを大量に消費しています。",
                suggestion: suggestion,
                // 終了を提案してよいプロセスのみ自動修復対象（高リスクなので個別承認になる）
                isAutoFixable: exp.quitRecommended,
                fixAction: exp.quitRecommended ? .quitApp : .none,
                fixTarget: name,
                rawData: [
                    "process": name,
                    "pid": "\(pid)",
                    "cpu_percent": String(format: "%.1f", cpu),
                    "what": exp.whatItIs,
                    "risk": exp.risk.label,
                    "risk_detail": exp.riskDetail
                ]
            ))
        }

        return findings
    }

    // MARK: - 2. Memory Diagnosis

    private func diagnoseMemory() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []
        let mem = processMonitor.systemMemory

        // Memory pressure
        if mem.freePercent < 10 {
            findings.append(DiagnosisFinding(
                category: .memory, severity: .critical,
                title: "メモリが極度に不足",
                detail: "空きメモリ \(mem.freeFormatted) (\(String(format: "%.0f", mem.freePercent))%) — 全体 \(mem.totalFormatted)",
                suggestion: "メモリタブの提案から、使っていないアプリやタブを終了してメモリを解放してください。",
                isAutoFixable: false, fixAction: .none,
                rawData: ["used_mb": "\(Int(mem.usedMB))", "free_mb": "\(Int(mem.freeMB))",
                          "total_mb": "\(Int(mem.totalMB))", "compressed_mb": "\(Int(mem.compressedMB))"]
            ))
        } else if mem.freePercent < 25 {
            findings.append(DiagnosisFinding(
                category: .memory, severity: .warning,
                title: "メモリ使用量が高い",
                detail: "空きメモリ \(mem.freeFormatted) (\(String(format: "%.0f", mem.freePercent))%)",
                suggestion: "メモリタブの提案から、バックグラウンドアプリの終了を検討してください。",
                isAutoFixable: false, fixAction: .none
            ))
        } else {
            findings.append(DiagnosisFinding(
                category: .memory, severity: .good,
                title: "メモリ使用量は正常",
                detail: "空きメモリ \(mem.freeFormatted) (\(String(format: "%.0f", mem.freePercent))%)",
                suggestion: "特に対処は不要です。"
            ))
        }

        // Swap check
        if mem.swapUsedMB > 2048 {
            findings.append(DiagnosisFinding(
                category: .memory, severity: .warning,
                title: "Swap使用量が高い (\(mem.swapFormatted))",
                detail: "物理メモリが不足しディスクにSwapしています。パフォーマンスが低下します。",
                suggestion: "メモリを大量に使っているアプリを終了してSwapを減らしてください。",
                rawData: ["swap_mb": "\(Int(mem.swapUsedMB))"]
            ))
        }

        // Memory leak candidates
        let leakThreshold = max(800, mem.totalMB * 0.08)
        for proc in processMonitor.topProcesses {
            if proc.memoryMB > leakThreshold && !proc.isSystemProcess {
                findings.append(DiagnosisFinding(
                    category: .memory, severity: .warning,
                    title: "\(proc.name) がメモリ \(proc.memoryFormatted) 使用",
                    detail: "全メモリの\(Int(proc.memoryMB / mem.totalMB * 100))%を占有しています。",
                    suggestion: "長時間起動している場合、再起動でメモリリークが解消される場合があります。",
                    isAutoFixable: true, fixAction: .quitApp, fixTarget: proc.name,
                    rawData: ["process": proc.name, "memory_mb": "\(Int(proc.memoryMB))"]
                ))
            }
        }

        return findings
    }

    // MARK: - 3. Disk Diagnosis

    private func diagnoseDisk() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []
        let storage = StorageAnalyzer().getStorageInfo()

        let freePercent = storage.totalGB > 0 ? (storage.freeGB / storage.totalGB) * 100 : 100

        if freePercent < 5 {
            findings.append(DiagnosisFinding(
                category: .disk, severity: .critical,
                title: "ストレージ容量がほぼ満杯",
                detail: "空き \(storage.freeFormatted) / 全体 \(storage.totalFormatted) (\(String(format: "%.0f", freePercent))%空き)",
                suggestion: "キャッシュ削除、不要ファイルの削除、大容量ファイルの移動を至急実施してください。",
                rawData: ["disk_free_gb": String(format: "%.1f", storage.freeGB),
                          "disk_total_gb": String(format: "%.1f", storage.totalGB)]
            ))
        } else if freePercent < 15 {
            findings.append(DiagnosisFinding(
                category: .disk, severity: .warning,
                title: "ストレージ容量が少ない",
                detail: "空き \(storage.freeFormatted) / 全体 \(storage.totalFormatted)",
                suggestion: "ストレージタブでスキャンを実行し、不要ファイルを整理することを推奨します。",
                rawData: ["disk_free_gb": String(format: "%.1f", storage.freeGB)]
            ))
        } else {
            findings.append(DiagnosisFinding(
                category: .disk, severity: .good,
                title: "ストレージ容量は十分",
                detail: "空き \(storage.freeFormatted) / 全体 \(storage.totalFormatted)",
                suggestion: "特に対処は不要です。"
            ))
        }

        // Check for large caches (Xcode DerivedData, npm, etc.)
        let home = NSHomeDirectory()
        let largeCachePaths: [(String, String)] = [
            ("\(home)/Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
            ("\(home)/Library/Developer/CoreSimulator", "iOS Simulator"),
            ("\(home)/Library/Caches/com.apple.dt.Xcode", "Xcode キャッシュ"),
            ("\(home)/.npm/_cacache", "npm キャッシュ"),
            ("\(home)/Library/Caches/Homebrew", "Homebrew キャッシュ"),
        ]

        for (path, name) in largeCachePaths {
            let sizeMB = optimizer.getDirectorySizeMB(path)
            if sizeMB > 500 {
                let sizeStr = sizeMB >= 1024 ? String(format: "%.1f GB", sizeMB / 1024) : String(format: "%.0f MB", sizeMB)
                findings.append(DiagnosisFinding(
                    category: .disk, severity: sizeMB > 5000 ? .warning : .info,
                    title: "\(name) が \(sizeStr) を使用",
                    detail: "削除しても自動再生成されるため安全に削除できます。",
                    suggestion: "ストレージタブから削除するか、「\(name)の削除」をAIチャットで相談してください。",
                    isAutoFixable: true,
                    fixAction: name.contains("DerivedData") ? .clearDerivedData : .clearCache,
                    fixTarget: path,
                    rawData: ["path": path, "size_mb": "\(Int(sizeMB))"]
                ))
            }
        }

        return findings
    }

    // MARK: - 4. iCloud Sync Diagnosis

    private func diagnoseICloudSync() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []

        // Check if fileproviderd or bird are using excessive CPU
        let highCPU = getHighCPUProcesses()
        let icloudProcesses = highCPU.filter {
            ["fileproviderd", "bird", "cloudd", "nsurlsessiond"].contains($0.name)
        }

        if !icloudProcesses.isEmpty {
            let totalCPU = icloudProcesses.reduce(0.0) { $0 + $1.cpu }
            let names = icloudProcesses.map { "\($0.name) (\(String(format: "%.0f", $0.cpu))%)" }.joined(separator: ", ")
            findings.append(DiagnosisFinding(
                category: .icloudSync, severity: totalCPU > 100 ? .critical : .warning,
                title: "iCloud同期がCPUを大量消費",
                detail: "プロセス: \(names)",
                suggestion: "iCloud Driveで大量のファイル（node_modulesなど）を同期していないか確認してください。.nosync化が有効です。",
                rawData: ["processes": names, "total_cpu": String(format: "%.0f", totalCPU)]
            ))
        }

        // Check for node_modules in iCloud Drive
        let icloudDocs = "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs"
        let nodeModulesInICloud = findNodeModulesInICloud(basePath: icloudDocs)
        if !nodeModulesInICloud.isEmpty {
            findings.append(DiagnosisFinding(
                category: .icloudSync, severity: .warning,
                title: "node_modules がiCloud Drive内に\(nodeModulesInICloud.count)件検出",
                detail: "node_modulesは再生成可能で、iCloud同期の大きな負荷になります。",
                suggestion: ".nosyncリネームにより同期対象から除外することを推奨します。",
                rawData: ["paths": nodeModulesInICloud.joined(separator: "\n")]
            ))
        }

        if icloudProcesses.isEmpty && nodeModulesInICloud.isEmpty {
            findings.append(DiagnosisFinding(
                category: .icloudSync, severity: .good,
                title: "iCloud同期は正常",
                detail: "iCloud関連プロセスの異常な負荷は検出されませんでした。",
                suggestion: "特に対処は不要です。"
            ))
        }

        return findings
    }

    // MARK: - 5. Security Software Diagnosis

    private func diagnoseSecuritySoftware() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []

        let knownAV: [String: String] = [
            "K7 AntiVirus": "K7 AntiVirus",
            "Norton": "Norton Security",
            "Avast": "Avast Security",
            "Kaspersky": "Kaspersky",
            "McAfee": "McAfee",
            "Bitdefender": "Bitdefender",
            "ESET": "ESET Cyber Security",
            "Sophos": "Sophos",
            "Malwarebytes": "Malwarebytes",
            "ClamXAV": "ClamXAV",
        ]

        for proc in processMonitor.processes {
            for (keyword, name) in knownAV {
                if proc.name.contains(keyword) {
                    let highCPU = getHighCPUProcesses().first { $0.name.contains(keyword) }
                    let cpuUsage = highCPU?.cpu ?? 0

                    if cpuUsage > 20 {
                        findings.append(DiagnosisFinding(
                            category: .securitySoftware, severity: .warning,
                            title: "\(name) が CPU \(String(format: "%.0f", cpuUsage))% 使用中",
                            detail: "リアルタイムスキャンがシステムに負荷をかけています。メモリ: \(proc.memoryFormatted)",
                            suggestion: "スキャンスケジュールの変更、または除外フォルダの設定を検討してください。",
                            rawData: ["av_name": name, "cpu": String(format: "%.0f", cpuUsage),
                                      "memory_mb": "\(Int(proc.memoryMB))"]
                        ))
                    } else {
                        findings.append(DiagnosisFinding(
                            category: .securitySoftware, severity: .info,
                            title: "\(name) が稼働中 (メモリ \(proc.memoryFormatted))",
                            detail: "現在のCPU負荷は正常範囲です。",
                            suggestion: "問題ありません。スキャン時に負荷が上がることがあります。",
                            rawData: ["av_name": name, "memory_mb": "\(Int(proc.memoryMB))"]
                        ))
                    }
                    break
                }
            }
        }

        if findings.isEmpty {
            findings.append(DiagnosisFinding(
                category: .securitySoftware, severity: .good,
                title: "サードパーティセキュリティソフトなし",
                detail: "macOS標準のセキュリティ機能（XProtect, Gatekeeper）で保護されています。",
                suggestion: "追加のウイルス対策ソフトは必須ではありませんが、必要に応じて導入できます。"
            ))
        }

        return findings
    }

    // MARK: - 6. Dev Tools Diagnosis

    private func diagnoseDevTools() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []
        let home = NSHomeDirectory()

        // Check for Docker
        let dockerProcs = processMonitor.processes.filter { $0.name.contains("Docker") || $0.name.contains("com.docker") }
        if !dockerProcs.isEmpty {
            let totalMB = dockerProcs.reduce(0.0) { $0 + $1.memoryMB }
            if totalMB > 1000 {
                let sizeStr = String(format: "%.1f GB", totalMB / 1024)
                findings.append(DiagnosisFinding(
                    category: .devTools, severity: .warning,
                    title: "Docker がメモリ \(sizeStr) 使用中",
                    detail: "Docker Desktop はバックグラウンドでも大量のメモリを消費します。",
                    suggestion: "使用していない時はDocker Desktopを終了すると大幅にメモリが解放されます。",
                    isAutoFixable: true, fixAction: .quitApp, fixTarget: "Docker",
                    rawData: ["docker_memory_mb": "\(Int(totalMB))"]
                ))
            }
        }

        // Check for Xcode-related caches
        let derivedData = "\(home)/Library/Developer/Xcode/DerivedData"
        let derivedSize = optimizer.getDirectorySizeMB(derivedData)
        if derivedSize > 2000 {
            let sizeStr = String(format: "%.1f GB", derivedSize / 1024)
            findings.append(DiagnosisFinding(
                category: .devTools, severity: .info,
                title: "Xcode DerivedData が \(sizeStr)",
                detail: "ビルドキャッシュが蓄積しています。削除してもビルド時に再生成されます。",
                suggestion: "容量が気になる場合は削除できます。次回ビルド時に再生成されます。",
                isAutoFixable: true, fixAction: .clearDerivedData, fixTarget: derivedData,
                rawData: ["path": derivedData, "size_mb": "\(Int(derivedSize))"]
            ))
        }

        // Check for node_modules in active projects
        let devDirs = ["\(home)/Desktop", "\(home)/Documents", "\(home)/Projects"]
        var totalNodeModules: Double = 0
        var nodeModulePaths: [String] = []
        for dir in devDirs {
            let found = findNodeModules(in: dir, maxDepth: 3)
            for path in found {
                let size = optimizer.getDirectorySizeMB(path)
                if size > 200 {
                    totalNodeModules += size
                    nodeModulePaths.append("\(path) (\(String(format: "%.0f MB", size)))")
                }
            }
        }

        if totalNodeModules > 1000 {
            findings.append(DiagnosisFinding(
                category: .devTools, severity: .info,
                title: "node_modules が合計 \(String(format: "%.1f GB", totalNodeModules / 1024))",
                detail: "\(nodeModulePaths.count)箇所: \(nodeModulePaths.prefix(3).joined(separator: ", "))",
                suggestion: "アクティブでないプロジェクトのnode_modulesを削除し、必要時にnpm installで再生成できます。",
                rawData: ["total_mb": "\(Int(totalNodeModules))", "count": "\(nodeModulePaths.count)"]
            ))
        }

        if findings.isEmpty {
            findings.append(DiagnosisFinding(
                category: .devTools, severity: .good,
                title: "開発ツールに問題なし",
                detail: "特に過大なキャッシュや負荷は検出されませんでした。",
                suggestion: "特に対処は不要です。"
            ))
        }

        return findings
    }

    // MARK: - 7. Browser & Apps Diagnosis (includes Font Health Check)

    private func diagnoseBrowserApps() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []

        // Font health check — detect if font DB was deleted or corrupted
        let fontDBPath = "\(NSHomeDirectory())/Library/Caches/com.apple.FontRegistry"

        // Check if system font directory is abnormally empty
        let systemFontCount = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Fonts").count) ?? 0
        let userFontCacheExists = FileManager.default.fileExists(atPath: fontDBPath)

        if systemFontCount < 10 {
            findings.append(DiagnosisFinding(
                category: .browserApp, severity: .critical,
                title: "システムフォントが不足している可能性",
                detail: "システムフォントフォルダに\(systemFontCount)個しかフォントがありません。ブラウザでのフォント表示に問題が出る可能性があります。",
                suggestion: "macOSのFont Bookアプリで「すべてのフォントを復元」を実行するか、macOSのアップデート/再インストールを検討してください。",
                isAutoFixable: true, fixAction: .openFontBook,
                rawData: ["system_font_count": "\(systemFontCount)"]
            ))
        }

        // Check for recently deleted font cache (could cause browser font issues)
        if !userFontCacheExists {
            // Check if any browser is running — if so, font issues may occur
            let browsersRunning = processMonitor.processes.contains { proc in
                ["Google Chrome", "Safari", "Firefox", "Arc"].contains(where: { proc.name.contains($0) })
            }
            if browsersRunning {
                findings.append(DiagnosisFinding(
                    category: .browserApp, severity: .info,
                    title: "フォントキャッシュが未構築",
                    detail: "フォントキャッシュ（FontRegistry）が存在しません。フォント表示が一時的に遅くなる場合があります。",
                    suggestion: "通常は自動再構築されます。フォント表示に問題がある場合はFont Bookで「すべてのフォントを復元」を実行してください。",
                    isAutoFixable: true, fixAction: .openFontBook,
                    rawData: ["font_cache_path": fontDBPath]
                ))
            }
        }

        // Browser cache sizes
        let caches = optimizer.getBrowserCacheInfo()
        let totalCacheMB = caches.reduce(0.0) { $0 + $1.sizeMB }
        if totalCacheMB > 500 {
            let browsers = caches.map { "\($0.browser): \(String(format: "%.0f MB", $0.sizeMB))" }.joined(separator: ", ")
            findings.append(DiagnosisFinding(
                category: .browserApp, severity: .info,
                title: "ブラウザキャッシュ合計 \(String(format: "%.0f MB", totalCacheMB))",
                detail: browsers,
                suggestion: "ブラウザキャッシュを削除するとストレージとメモリの両方が改善します。",
                isAutoFixable: true, fixAction: .clearBrowserCache,
                rawData: ["total_cache_mb": "\(Int(totalCacheMB))"]
            ))
        }

        // Heavy Chrome extensions
        let extensions = optimizer.getChromeExtensions()
        let heavyExts = extensions.filter { $0.sizeMB > 10 }
        if heavyExts.count > 3 {
            let extNames = heavyExts.prefix(5).map { "\($0.name) (\(String(format: "%.0f MB", $0.sizeMB)))" }.joined(separator: ", ")
            findings.append(DiagnosisFinding(
                category: .browserApp, severity: .info,
                title: "重いChrome拡張機能が\(heavyExts.count)個",
                detail: extNames,
                suggestion: "不要な拡張機能をchrome://extensionsから無効化するとメモリが軽減されます。",
                rawData: ["heavy_ext_count": "\(heavyExts.count)"]
            ))
        }

        // Background apps using lots of memory
        let bgThreshold: Double = 300
        let bgApps = processMonitor.topProcesses.filter { proc in
            !proc.isSystemProcess && proc.memoryMB > bgThreshold &&
            ["Adobe Creative Cloud", "Spotify", "Discord", "Docker", "Slack", "Teams",
             "Zoom", "LINE", "Steam"].contains(where: { proc.name.contains($0) })
        }
        if !bgApps.isEmpty {
            let totalBG = bgApps.reduce(0.0) { $0 + $1.memoryMB }
            let appNames = bgApps.map { "\($0.name): \($0.memoryFormatted)" }.joined(separator: ", ")
            findings.append(DiagnosisFinding(
                category: .browserApp, severity: .info,
                title: "バックグラウンドアプリがメモリ \(String(format: "%.0f MB", totalBG)) 使用",
                detail: appNames,
                suggestion: "使用していないバックグラウンドアプリを終了するとメモリが解放されます。",
                isAutoFixable: false,
                rawData: ["bg_apps": appNames, "total_mb": "\(Int(totalBG))"]
            ))
        }

        if findings.isEmpty {
            findings.append(DiagnosisFinding(
                category: .browserApp, severity: .good,
                title: "ブラウザ・アプリは正常",
                detail: "過大なキャッシュやバックグラウンドアプリの問題は検出されませんでした。",
                suggestion: "特に対処は不要です。"
            ))
        }

        return findings
    }

    // MARK: - 8. Login Items Diagnosis

    private func diagnoseLoginItems() async -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []

        let loginItems = optimizer.getLoginItems(processes: processMonitor.processes)
        let runningItems = loginItems.filter { $0.isRunning }
        let totalLoginMB = runningItems.reduce(0.0) { $0 + $1.memoryMB }

        if runningItems.count > 5 && totalLoginMB > 500 {
            let itemNames = runningItems.prefix(5).map { "\($0.name) (\(String(format: "%.0f MB", $0.memoryMB)))" }.joined(separator: ", ")
            findings.append(DiagnosisFinding(
                category: .loginItems, severity: .warning,
                title: "ログイン項目が\(runningItems.count)個稼働中 (合計 \(String(format: "%.0f MB", totalLoginMB)))",
                detail: itemNames,
                suggestion: "不要なログイン項目はシステム設定 > ログイン項目から無効化できます。",
                isAutoFixable: true, fixAction: .openSystemSettings,
                rawData: ["count": "\(runningItems.count)", "total_mb": "\(Int(totalLoginMB))"]
            ))
        } else if !runningItems.isEmpty {
            findings.append(DiagnosisFinding(
                category: .loginItems, severity: .info,
                title: "ログイン項目: \(runningItems.count)個稼働中",
                detail: "合計メモリ使用量: \(String(format: "%.0f MB", totalLoginMB))",
                suggestion: "現在の数は正常範囲です。不要なものがあれば無効化できます。"
            ))
        } else {
            findings.append(DiagnosisFinding(
                category: .loginItems, severity: .good,
                title: "ログイン項目に問題なし",
                detail: "ログイン時の自動起動アプリによる過大なリソース消費はありません。",
                suggestion: "特に対処は不要です。"
            ))
        }

        return findings
    }

    // MARK: - Score Calculation

    private func calculateOverallScore(findings: [DiagnosisFinding]) -> Int {
        var score = 100

        for finding in findings {
            switch finding.severity {
            case .critical: score -= 20
            case .warning: score -= 8
            case .info: score -= 2
            case .good: break
            }
        }

        return max(0, min(100, score))
    }

    // MARK: - System Snapshot

    private func captureSystemSnapshot() -> SystemSnapshot {
        let mem = processMonitor.systemMemory
        let storage = StorageAnalyzer().getStorageInfo()
        let loadAvg = getLoadAverage()

        let topProcs = processMonitor.topProcesses.prefix(10).map {
            "\($0.name): \($0.memoryFormatted)"
        }

        return SystemSnapshot(
            totalRAM_MB: Int(mem.totalMB),
            usedRAM_MB: Int(mem.usedMB),
            freeRAM_MB: Int(mem.freeMB),
            compressedRAM_MB: Int(mem.compressedMB),
            swapUsedMB: Int(mem.swapUsedMB),
            diskTotalGB: Int(storage.totalGB),
            diskFreeGB: Int(storage.freeGB),
            loadAverage: loadAvg.map { String(format: "%.1f", $0) }.joined(separator: "/"),
            topProcesses: Array(topProcs)
        )
    }

    // MARK: - Helper Methods

    /// Get load average from sysctl
    private func getLoadAverage() -> [Double] {
        var loadAvg = [Double](repeating: 0, count: 3)
        getloadavg(&loadAvg, 3)
        return loadAvg
    }

    /// Get processes using high CPU via ps command
    private func getHighCPUProcesses() -> [(pid: Int32, name: String, cpu: Double)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -c: 実行ファイル名のみ（フルパスではないので16文字切り詰めが起きない）
        //     → "Aq"/"Library"/"kurosuken" のような誤名を防ぎ、正しいプロセス名を得る
        // pid= %cpu= comm= : ヘッダ無しで pid・CPU・名前を出力
        process.arguments = ["-eo", "pid=,%cpu=,comm=", "-c", "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [(pid: Int32, name: String, cpu: Double)] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // "PID %CPU COMM(空白を含みうる)" 形式。先頭2トークンが pid と %cpu、残りが名前。
            let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3,
                  let pid = Int32(tokens[0]),
                  let cpu = Double(tokens[1]),
                  cpu > 15 else { continue }

            let name = tokens[2...].joined(separator: " ")
            results.append((pid, name, cpu))
        }

        return Array(results.prefix(10))
    }

    /// Find node_modules directories in iCloud Drive
    private func findNodeModulesInICloud(basePath: String) -> [String] {
        var results: [String] = []
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(atPath: basePath) else { return [] }

        for item in items {
            let fullPath = "\(basePath)/\(item)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            if item == "node_modules" {
                results.append(fullPath)
            } else if !item.hasPrefix(".") {
                // Search one level deeper (project/node_modules)
                if let subItems = try? fm.contentsOfDirectory(atPath: fullPath) {
                    for sub in subItems where sub == "node_modules" {
                        results.append("\(fullPath)/\(sub)")
                    }
                }
            }
        }

        return results
    }

    /// Find node_modules in local directories
    private func findNodeModules(in basePath: String, maxDepth: Int) -> [String] {
        var results: [String] = []
        let fm = FileManager.default

        guard maxDepth > 0, let items = try? fm.contentsOfDirectory(atPath: basePath) else { return [] }

        for item in items {
            let fullPath = "\(basePath)/\(item)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            if item == "node_modules" {
                results.append(fullPath)
            } else if !item.hasPrefix(".") && item != "Library" {
                results.append(contentsOf: findNodeModules(in: fullPath, maxDepth: maxDepth - 1))
            }
        }

        return results
    }
}
