import AppKit
import UserNotifications

/// アプリ内自動アップデート（App Store 外配布用の軽量版）。
///
/// 仕組み：GitHub Release の `latest.json`（build番号・DMS URL）を取得し、
/// 現在の CFBundleVersion より新しければ DMG をダウンロード→検証済み .app を
/// /Applications へ差し替え→再起動する。差し替えは「自プロセス終了を待つ」ヘルパで安全に行う。
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    /// GitHub Release の "latest" を常に指す固定 URL（毎リリースで中身が更新される）
    private let manifestURL = URL(string: "https://github.com/ken-kurosu/AIMacOptimizer/releases/latest/download/latest.json")!
    private let releasesPageURL = URL(string: "https://github.com/ken-kurosu/AIMacOptimizer/releases/latest")!
    private let autoKey = "autoUpdateEnabled"
    private let lastCheckKey = "updateLastCheck"
    private let checkInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isBusy = false

    private init() {}

    var autoUpdateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) == nil ? true : UserDefaults.standard.bool(forKey: autoKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0 }
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    private struct Manifest: Decodable {
        let build: Int
        let version: String
        let url: String
        let notes: String?
    }

    // MARK: - 定期チェック（AppDelegate のタイマーから）
    func autoCheckIfDue() {
        guard autoUpdateEnabled else { return }
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard now - last >= checkInterval else { return }
        UserDefaults.standard.set(now, forKey: lastCheckKey)
        Task { await check(userInitiated: false) }
    }

    // MARK: - チェック本体
    /// userInitiated=true（設定の「アップデートを確認」）なら結果を必ず statusMessage に出す。
    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if userInitiated { statusMessage = "確認中…" }

        guard let m = await fetchManifest() else {
            if userInitiated { statusMessage = "更新情報を取得できませんでした。時間をおいて再試行してください。" }
            return
        }
        guard m.build > currentBuild, let dmgURL = URL(string: m.url) else {
            if userInitiated { statusMessage = "最新版を使用中です（v\(currentVersion)）。" }
            return
        }

        // 新しい版がある
        if !autoUpdateEnabled {
            // 自動OFF：通知だけして、実行はユーザー操作に委ねる
            if userInitiated {
                statusMessage = "v\(m.version) をダウンロード中…"
                await downloadAndInstall(dmgURL: dmgURL, version: m.version)
            } else {
                notify(title: "新しいバージョン v\(m.version) があります",
                       body: "設定 → 情報 →「アップデートを確認」から更新できます。")
            }
            return
        }

        // 自動ON：ダウンロードして差し替え・再起動
        statusMessage = "v\(m.version) をダウンロード中…"
        await downloadAndInstall(dmgURL: dmgURL, version: m.version)
    }

    func openReleasesPage() { NSWorkspace.shared.open(releasesPageURL) }

    // MARK: - 取得
    private func fetchManifest() async -> Manifest? {
        var req = URLRequest(url: manifestURL)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - ダウンロード＆差し替え
    private func downloadAndInstall(dmgURL: URL, version: String) async {
        guard let (tmp, resp) = try? await URLSession.shared.download(from: dmgURL),
              (resp as? HTTPURLResponse)?.statusCode == 200 else {
            statusMessage = "ダウンロードに失敗しました。"; return
        }
        let dmgPath = NSTemporaryDirectory() + "AIMacOptimizer-update.dmg"
        try? FileManager.default.removeItem(atPath: dmgPath)
        do { try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: dmgPath)) }
        catch { statusMessage = "更新ファイルの保存に失敗しました。"; return }

        guard let mount = mountDMG(dmgPath) else { statusMessage = "更新DMGをマウントできませんでした。"; return }
        let appName = "AI Mac Optimizer.app"
        let srcApp = mount + "/" + appName
        guard FileManager.default.fileExists(atPath: srcApp) else {
            detachDMG(mount); statusMessage = "更新用アプリが見つかりません。"; return
        }
        // 署名を保ったまま temp へ複製（DMGは後で外す）
        let staged = NSTemporaryDirectory() + appName
        try? FileManager.default.removeItem(atPath: staged)
        _ = runProcess("/usr/bin/ditto", [srcApp, staged])
        detachDMG(mount)
        guard FileManager.default.fileExists(atPath: staged) else {
            statusMessage = "更新の準備に失敗しました。"; return
        }

        // 自プロセス終了を待って /Applications を差し替え→再起動するヘルパ
        let dest = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptPath = NSTemporaryDirectory() + "amo-update.sh"
        let script = """
        #!/bin/bash
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.4; done
        /usr/bin/ditto "\(staged)" "\(dest)"
        /bin/rm -rf "\(staged)"
        /bin/rm -f "\(dmgPath)"
        /usr/bin/open "\(dest)"
        """
        do { try script.write(toFile: scriptPath, atomically: true, encoding: .utf8) }
        catch { statusMessage = "更新の起動に失敗しました。"; return }
        _ = runProcess("/bin/chmod", ["+x", scriptPath])

        notify(title: "アップデートしています…", body: "v\(version) に更新して自動的に再起動します。")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptPath]
        do { try p.run() } catch { statusMessage = "更新の起動に失敗しました。"; return }

        // 差し替えのため終了（ヘルパが再起動する）
        NSApp.terminate(nil)
    }

    // MARK: - DMG / Process ユーティリティ
    private func mountDMG(_ path: String) -> String? {
        let out = runProcess("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", path])
        // "/dev/diskXsY   Apple_HFS   /Volumes/AI Mac Optimizer" のような行から mount point を拾う
        for line in out.split(separator: "\n") {
            if let range = line.range(of: "/Volumes/") {
                return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func detachDMG(_ mount: String) {
        _ = runProcess("/usr/bin/hdiutil", ["detach", mount, "-force"])
    }

    @discardableResult
    private func runProcess(_ launch: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
