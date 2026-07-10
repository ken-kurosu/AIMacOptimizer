import SwiftUI
import AppKit

/// 初回起動時に一度だけ表示するオンボーディング。
/// ここでアプリをアクティブ化した状態で通知許可を要求することで、
/// 「メニューバー常駐アプリが非アクティブのまま要求してダイアログが前面に出ない」問題を回避する。
/// 完了するとウィンドウを閉じ、以降はメニューバー常駐（LSUIElement）として動く。
struct OnboardingView: View {
    /// 通知許可ダイアログを出す（応答後に granted を返す）
    let onRequestNotifications: (@escaping (Bool) -> Void) -> Void
    /// オンボーディングを完了してメニューバーへ
    let onFinish: () -> Void

    @State private var phase: Phase = .intro
    @State private var notifGranted: Bool?

    enum Phase { case intro, permissions, done }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー（ロゴ）
            ZStack {
                LinearGradient(colors: [Color(red: 0, green: 0.44, blue: 0.89), Color(red: 0.05, green: 0.58, blue: 0.53)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.white)
                    Text("AI Mac Optimizer")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(height: 150)

            Group {
                switch phase {
                case .intro: introView
                case .permissions: permissionsView
                case .done: doneView
                }
            }
            .padding(28)
        }
        .frame(width: 460)
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Macを、実測でもっと軽く。")
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                bullet("memorychip", "ワンクリックで使われていないメモリを解放（実測表示）")
                bullet("internaldrive", "ディスクを分析し、安全に消せるものをワンボタンで整理")
                bullet("bell.badge", "空き容量が減る前や不調の兆しを、通知でお知らせ")
                bullet("lock.shield", "データはMacの外に出ません。削除はゴミ箱経由で復元可能")
            }
            Text("常にメニューバーに常駐し、必要な時だけ静かに働きます。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button(action: { phase = .permissions }) {
                Text("はじめる")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Permissions

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通知を有効にしましょう")
                .font(.system(size: 16, weight: .semibold))
            Text("メモリ/ディスクの圧迫や、空き容量が少なくなる前の警告をお届けします。特に「ディスクが満杯になる前の緊急アラート」は、通知が有効でないと届きません。")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bullet("bell.badge", "満杯前の警告・緊急アラート")
                bullet("chart.line.uptrend.xyaxis", "週次の最適化レポート")
            }

            if let granted = notifGranted {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(granted ? .green : .orange)
                    Text(granted ? "通知が有効になりました。" : "通知が許可されませんでした。あとで システム設定 → 通知 から有効にできます。")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if notifGranted == nil {
                    Button(action: requestNotifications) {
                        Text("通知を許可する")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("あとで") { phase = .done }
                        .controlSize(.large)
                } else {
                    Button(action: { phase = .done }) {
                        Text("次へ")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("準備ができました")
                .font(.system(size: 17, weight: .semibold))
            Text("これからは画面右上の メニューバー のアイコンから、いつでも最適化・診断ができます。")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                Text("メニューバーの「memorychip」アイコンを探してください")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)

            Button(action: onFinish) {
                Text("メニューバーで始める")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func requestNotifications() {
        onRequestNotifications { granted in
            notifGranted = granted
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
