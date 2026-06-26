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
    @State private var rangeHours: Double = 24

    var body: some View {
        let data = history.recent(hours: rangeHours)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                Text("健康状態の推移")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $rangeHours) {
                    Text("24時間").tag(24.0)
                    Text("7日").tag(168.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }

            if data.count < 2 {
                Text("データ収集中です。バックグラウンドで10分ごとに記録し、しばらくすると推移が表示されます。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                metricRow("メモリ使用率", values: data.map(\.memUsedPercent), unit: "%", color: .blue)
                metricRow("Swap", values: data.map(\.swapMB), unit: "MB", color: .orange)
                metricRow("ディスク空き", values: data.map(\.diskFreePercent), unit: "%", color: .green)
                metricRow("CPU負荷", values: data.map(\.loadAvg1), unit: "", color: .red)
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Text("最小\(fmt(minV)) / 最大\(fmt(maxV))\(unit.isEmpty ? "" : unit)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 96, alignment: .leading)

            Sparkline(values: values, color: color)
                .frame(height: 26)

            Text("\(fmt(current))\(unit)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
