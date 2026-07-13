import Foundation

/// アプリ内の匿名使用イベント計測（GA4 Measurement Protocol）。
///
/// 送るのは「どのタブ/ボタンを押したか」等の**匿名の操作イベントのみ**。
/// ファイル名・メモリ内容・個人を特定する情報は一切送らない（ブランド「データはローカルから出ない」と両立）。
/// 設定でいつでもオフにできる。
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let measurementID = "G-W0CQVD8YXN"
    private let apiSecret = "ZnSahTonTQybiFR0jAXy7g"
    private let endpoint = "https://www.google-analytics.com/mp/collect"

    private let enabledKey = "analyticsEnabled"
    private let clientIDKey = "analyticsClientID"

    private init() {}

    /// 匿名の使用統計を送るか（既定ON・設定でオフ可）
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 端末に紐づかない匿名ID（初回にランダム生成して保存）。個人特定はできない。
    private var clientID: String {
        if let id = UserDefaults.standard.string(forKey: clientIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: clientIDKey)
        return id
    }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var tierName: String { LicenseManager.shared.currentTier.isPro ? "pro" : "free" }

    /// イベント送信（fire-and-forget・失敗しても無視）。
    /// event: GA4規則に合わせ小文字/英数/アンダースコア。params は文字列/数値のみ。
    func track(_ event: String, _ params: [String: Any] = [:]) {
        guard enabled else { return }
        guard let url = URL(string: "\(endpoint)?measurement_id=\(measurementID)&api_secret=\(apiSecret)") else { return }

        var eventParams: [String: Any] = params
        eventParams["app_version"] = appVersion
        eventParams["tier"] = tierName
        // GA4 で「エンゲージ」扱いにするため
        eventParams["engagement_time_msec"] = 1

        let body: [String: Any] = [
            "client_id": clientID,
            "events": [["name": sanitize(event), "params": eventParams]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }

    /// GA4のイベント名規則(先頭英字・英数と_・40字以内)に寄せる
    private func sanitize(_ name: String) -> String {
        let allowed = name.lowercased().map { ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" }
        var s = String(allowed)
        if let first = s.first, !first.isLetter { s = "e_" + s }
        return String(s.prefix(40))
    }
}
