import Foundation

/// アプリ内の匿名使用イベント計測（GA4 Measurement Protocol）。
///
/// 送るのは「起動した・どのタブを見た・ライセンスを有効化した」等の**匿名の利用イベントのみ**。
/// ファイル名・メモリ内容・診断結果・個人を特定する情報は一切送らない。
/// 既定ON（まだ一度も設定していない場合）。初回画面と一度きりのお知らせで明示し、
/// 設定のスイッチ1つでいつでもOFFにできる。自分でOFFにした人の選択は尊重する。
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let measurementID = "G-W0CQVD8YXN"
    private let apiSecret = "ZnSahTonTQybiFR0jAXy7g"
    private let endpoint = "https://www.google-analytics.com/mp/collect"

    private let enabledKey = "analyticsEnabled"
    private let clientIDKey = "analyticsClientID"
    private let firstOpenSentKey = "analyticsFirstOpenSent"
    private let lastDailyActiveKey = "analyticsLastDailyActive"
    private let noticeAcknowledgedKey = "analyticsNoticeAcknowledged"

    private init() {}

    /// 匿名の使用統計を送るか。未設定なら ON（既定ON）、明示的にOFFにした人はOFFのまま。
    /// ※ 設定画面の @AppStorage("analyticsEnabled") の既定値もこれと揃えて true にしている。
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 既定ONになったことを、まだユーザーに伝えていないか（初回画面 or 一度きりのお知らせで伝える）
    var needsNotice: Bool { !UserDefaults.standard.bool(forKey: noticeAcknowledgedKey) }

    func acknowledgeNotice() { UserDefaults.standard.set(true, forKey: noticeAcknowledgedKey) }

    /// 起動時に呼ぶ。初回だけ first_open、毎回 app_open、日付が変わっていれば daily_active を送る。
    /// （メニューバー常駐で起動は稀なため、稼働数は daily_active で数える）
    func trackLaunch() {
        guard enabled else { return }
        if !UserDefaults.standard.bool(forKey: firstOpenSentKey) {
            track("first_open")
            UserDefaults.standard.set(true, forKey: firstOpenSentKey)
        }
        track("app_open")
        trackDailyActiveIfNeeded()
    }

    /// 1日1回だけ daily_active を送る（常駐中は定期タイマーから呼ぶ）。
    func trackDailyActiveIfNeeded() {
        guard enabled else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let today = f.string(from: Date())
        guard UserDefaults.standard.string(forKey: lastDailyActiveKey) != today else { return }
        UserDefaults.standard.set(today, forKey: lastDailyActiveKey)
        track("daily_active")
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
