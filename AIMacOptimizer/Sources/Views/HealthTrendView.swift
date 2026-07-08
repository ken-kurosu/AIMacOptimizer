import SwiftUI

/// 軽量スパークライン（Path描画のみ。Chartsフレームワーク不使用でバイナリも軽い）
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let range = max(maxV - minV, 0.0001)
                let stepX = geo.size.width / CGFloat(values.count - 1)

                // 塗り（薄く）
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.12))

                // 線
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

/// 健康状態の推移（メモリ/Swap/ディスク空き/CPU負荷）を表示
struct HealthTrendView: View {
    @ObservedObject private var history = HealthHistory.shared
    @ObservedObject private var license = LicenseManager.shared
    @State private var rangeHours: Double = 24

    var body: some View {
        // 履歴の壁: Free は直近24時間まで。長期(7日/30日)は Pro で解放。
        let isPro = license.currentTier.isPro
        let effectiveHours = isPro ? rangeHours : 24
        let data = history.recent(hours: effectiveHours)
        let proRangeLocked = !isPro && rangeHours > 24

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text(L10n.healthTrend)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $rangeHours) {
                    Text(L10n.last24h).tag(24.0)
                    Text(L10n.last7d).tag(168.0)
                    Text(L10n.last30d).tag(720.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if proRangeLocked {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(L10n.healthTrendProLock)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            if data.count < 2 {
                Text(L10n.collectingData)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                // 実際にカバーしている範囲を明示。記録期間がまだ短いと「24時間」と「7日」で
                // 同じデータになる（タブを変えても変化しない）ため、故障ではないと分かるようにする。
                Text(coverageCaption(data, requestedHours: effectiveHours))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                metricRow(L10n.memoryUsagePercent, values: data.map(\.memUsedPercent), unit: "%", color: .blue)
                // Swap は大きいと GB 表示（他画面の単位表記と揃える）
                if (data.map(\.swapMB).max() ?? 0) >= 1024 {
                    metricRow(L10n.swap, values: data.map { $0.swapMB / 1024 }, unit: "GB", color: .orange)
                } else {
                    metricRow(L10n.swap, values: data.map(\.swapMB), unit: "MB", color: .orange)
                }
                metricRow(L10n.diskFree, values: data.map(\.diskFreePercent), unit: "%", color: .green)
                metricRow(L10n.cpuLoad, values: data.map(\.loadAvg1), unit: "", color: .red)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func metricRow(_ title: String, values: [Double], unit: String, color: Color) -> some View {
        let current = values.last ?? 0
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        // 期間平均。24時間と7日で値が変わるのはここ（min/maxは安定しがちなので平均を主役にする）
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let unitSuffix = unit.isEmpty ? "" : unit
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Text(L10n.trendStat(avg: fmt(avg), unit: unitSuffix, minV: fmt(minV), maxV: fmt(maxV)))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 104, alignment: .leading)

            Sparkline(values: values, color: color)
                .frame(height: 26)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(fmt(current))\(unitSuffix)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .monospacedDigit()
                Text(L10n.current_)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, alignment: .trailing)
        }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    /// 実データの範囲と件数を文章化し、選んだ期間分のデータがまだ無い場合はそれを明示する。
    /// （データが1.5日分しか無いのに「7日」を選んでも中身は同じ＝故障ではない、と分かるように）
    private func coverageCaption(_ data: [HealthSnapshot], requestedHours: Double) -> String {
        guard let first = data.first?.date, let last = data.last?.date else { return "" }
        let spanHours = last.timeIntervalSince(first) / 3600
        let spanText: String
        if spanHours >= 24 {
            spanText = L10n.coverageSpanDays(String(format: "%.1f", spanHours / 24))
        } else if spanHours >= 1 {
            spanText = L10n.coverageSpanHours(String(format: "%.1f", spanHours))
        } else {
            spanText = L10n.coverageSpanMinutes(String(format: "%.0f", spanHours * 60))
        }
        // 選択期間に対してデータが足りているか（9割未満なら「まだ揃っていない」と案内）
        let reqLabel = requestedHours >= 48 ? L10n.rangeLabelDays(String(format: "%.0f", requestedHours / 24)) : L10n.rangeLabel24h
        if spanHours < requestedHours * 0.9 {
            return L10n.coverageIncomplete(span: spanText, count: data.count, reqLabel: reqLabel)
        }
        return L10n.coverageComplete(span: spanText, count: data.count)
    }
}
