import SwiftUI

/// Deep Diagnosis tab view — shows diagnosis results with overall score
struct DiagnosisView: View {
    @ObservedObject var engine: DeepDiagnosisEngine
    @ObservedObject var license: LicenseManager
    let onOpenChat: () -> Void
    
    @State private var fixResults: [String] = []
    @State private var isFixing = false
    @State private var showFixResults = false
    @State private var pendingRisky: [DiagnosisFinding] = []
    @State private var riskyResults: [String] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if engine.isRunning {
                    runningView
                } else if let report = engine.lastReport {
                    reportView(report)
                } else {
                    emptyView
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "stethoscope")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            Text("Deep Diagnosis")
                .font(.headline)
            Text("CPU・メモリ・ストレージ・iCloud同期など\n9項目を包括的に診断します")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task { await engine.runFullDiagnosis() }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("診断を開始")
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
        .padding()
    }
    
    // MARK: - Running State
    private var runningView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            Text(engine.currentStep)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Int(engine.progress * 100))%")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Report View
    private func reportView(_ report: DiagnosisReport) -> some View {
        VStack(spacing: 0) {
            // Overall Score
            scoreHeader(report)
            
            Divider()
            
            // Fix All button (if there are auto-fixable findings)
            let fixableCount = report.findings.filter { $0.isAutoFixable && $0.fixAction != .none }.count
            if fixableCount > 0 {
                fixAllSection(fixableCount: fixableCount)
                Divider()
            }
            
            // Fix results banner
            if showFixResults && !fixResults.isEmpty {
                fixResultsBanner
                Divider()
            }
            
            // Findings list
            findingsList(report)
            
            Divider()
            
            // Action buttons
            actionButtons(report)
        }
    }
    
    // MARK: - Fix All Section
    private func fixAllSection(fixableCount: Int) -> some View {
        VStack(spacing: 6) {
            Button(action: {
                Task {
                    isFixing = true
                    showFixResults = false
                    riskyResults = []
                    let result = await engine.executeAllFixes()
                    fixResults = result.messages
                    pendingRisky = result.pendingRisky
                    isFixing = false
                    showFixResults = true
                }
            }) {
                HStack(spacing: 6) {
                    if isFixing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isFixing ? "修復中..." : "全て修復 (\(fixableCount)件)")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isFixing)
            .padding(.horizontal, 16)
            
            Text("自動修復可能な項目をまとめて実行し、再診断します")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Fix Results Banner
    private var fixResultsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("修復完了")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { showFixResults = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            ForEach(fixResults, id: \.self) { msg in
                Text("• \(msg)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // 高リスク項目（アプリ/プロセス終了）の個別承認
            if !pendingRisky.isEmpty {
                Divider().padding(.vertical, 2)
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("個別の承認が必要な操作")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text("以下はリスクがあるため自動実行していません。内容を確認して、実行するものだけ承認してください。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                ForEach(pendingRisky) { finding in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.title)
                            .font(.system(size: 11, weight: .medium))
                        if let what = finding.rawData["what"] {
                            Text(what)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        if let risk = finding.rawData["risk"], let detail = finding.rawData["risk_detail"] {
                            Text("終了リスク \(risk)：\(detail)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Spacer()
                            Button("スキップ") {
                                pendingRisky.removeAll { $0.id == finding.id }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("承認して実行") {
                                Task {
                                    let msg = await engine.executeFix(for: finding)
                                    riskyResults.append(msg)
                                    pendingRisky.removeAll { $0.id == finding.id }
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }

            ForEach(riskyResults, id: \.self) { msg in
                Text("• \(msg)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private func scoreHeader(_ report: DiagnosisReport) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("診断結果")
                    .font(.headline)
                Spacer()
                Text(report.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(report.overallScore) / 100)
                    .stroke(scoreColor(report.overallScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(report.overallScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(report.overallScore))
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 90, height: 90)
            
            HStack(spacing: 12) {
                if report.criticalCount > 0 {
                    Label("\(report.criticalCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                if report.warningCount > 0 {
                    Label("\(report.warningCount)", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                let goodCount = report.findings.filter { $0.severity == .good }.count
                if goodCount > 0 {
                    Label("\(goodCount)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
    }
    
    private func findingsList(_ report: DiagnosisReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(report.findings.sorted { $0.severity < $1.severity }) { finding in
                FindingRow(finding: finding, engine: engine)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func actionButtons(_ report: DiagnosisReport) -> some View {
        VStack(spacing: 8) {
            // Pro upgrade prompt for Free users
            if !license.currentTier.isPro {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proでもっと活用")
                            .font(.system(size: 11, weight: .semibold))
                        Text("AIチャット・無制限診断・自動最適化")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { SettingsWindowController.shared.showSettings() }) {
                        Text("アップグレード")
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
                .padding(8)
                .background(Color.yellow.opacity(0.06))
                .cornerRadius(8)
            }

            // Chat button (Pro feature or limited for Free)
            Button(action: onOpenChat) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("AIに相談する")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            
            // Re-run diagnosis
            Button(action: {
                Task { await engine.runFullDiagnosis() }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("再診断")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Helpers
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}

// MARK: - Finding Row
struct FindingRow: View {
    let finding: DiagnosisFinding
    let engine: DeepDiagnosisEngine
    @State private var isExpanded = false
    @State private var fixMessage: String?
    @State private var isFixingThis = false
    @State private var showProcessDetail = false

    private func riskColor(_ risk: String) -> Color {
        switch risk {
        case "高": return .red
        case "中": return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Image(systemName: finding.severity.icon)
                        .font(.system(size: 12))
                        .foregroundColor(severityColor)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Text(finding.category.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Show fix badge on collapsed row if auto-fixable
                    if !isExpanded && finding.isAutoFixable && finding.fixAction != .none {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(finding.suggestion)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                    }

                    // プロセスの詳細説明（何のプロセスか・終了リスクと程度）
                    if let what = finding.rawData["what"] {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showProcessDetail.toggle() } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                Text(showProcessDetail ? "詳細を閉じる" : "詳細を確認")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                        if showProcessDetail {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(what)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let risk = finding.rawData["risk"] {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.shield.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(riskColor(risk))
                                        Text("終了リスク: \(risk)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(riskColor(risk))
                                    }
                                }
                                if let detail = finding.rawData["risk_detail"] {
                                    Text(detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                            .padding(.top, 2)
                        }
                    }

                    // Auto-fix button
                    if finding.isAutoFixable && finding.fixAction != .none {
                        Button(action: {
                            Task {
                                isFixingThis = true
                                fixMessage = nil
                                let result = await engine.executeFix(for: finding)
                                fixMessage = result
                                isFixingThis = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isFixingThis {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: finding.fixAction.icon)
                                        .font(.system(size: 10))
                                }
                                Text(finding.fixAction.buttonLabel)
                                    .font(.system(size: 11))
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isFixingThis)
                        .padding(.top, 2)
                    }
                    
                    // Fix result message
                    if let msg = fixMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? Color.gray.opacity(0.04) : Color.clear)
        .cornerRadius(6)
    }
    
    private var severityColor: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .good: return .green
        }
    }
}
