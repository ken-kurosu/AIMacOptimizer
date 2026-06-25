import Foundation
import AppKit

/// プロセス終了のリスク度
enum ProcessRiskLevel: String {
    case low = "低"
    case medium = "中"
    case high = "高"

    var label: String { rawValue }
    var colorName: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}

/// あるプロセスが「何者か」「終了するとどうなるか」の説明
struct ProcessExplanation {
    /// このプロセスは何か
    let whatItIs: String
    /// 終了時のリスク度
    let risk: ProcessRiskLevel
    /// 終了するとどうなるか（具体的な影響）
    let riskDetail: String
    /// 終了を提案してよいか（false=システム基幹のため終了ボタンを出さない）
    let quitRecommended: Bool
}

/// プロセス名から「何のプロセスか・終了リスク」を判定する知識ベース。
/// 既知プロセスは個別解説、未知はパス/起動アプリ種別からヒューリスティックに判定する。
enum ProcessCatalog {

    /// 終了すると macOS が不安定になる基幹プロセス（終了ボタンを出さない）
    private static let systemCritical: [String: String] = [
        "WindowServer": "画面表示を司る macOS の中核プロセス",
        "kernel_task": "カーネル（OSの心臓部）。CPU温度管理も担う",
        "launchd": "全プロセスの起動・管理を行う最上位プロセス",
        "coreaudiod": "システム全体の音声を処理するプロセス",
        "loginwindow": "ログインセッションを管理するプロセス",
        "SystemUIServer": "メニューバー等のシステムUIを描画するプロセス",
        "Dock": "Dock とミッションコントロールを管理するプロセス",
        "Finder": "ファイル管理とデスクトップを担うプロセス",
        "ControlCenter": "コントロールセンターを管理するプロセス",
        "mds": "Spotlight の検索インデックスを管理するプロセス",
        "mds_stores": "Spotlight の検索インデックスを管理するプロセス",
        "mdworker": "Spotlight のインデックス作成ワーカー",
        "secd": "キーチェーン等のセキュリティを担うプロセス",
        "trustd": "証明書の信頼性を検証するプロセス",
        "powerd": "電源管理を行うプロセス",
        "configd": "ネットワーク構成を管理するプロセス",
        "backupd": "Time Machine バックアップを行うプロセス",
    ]

    /// クラウド同期系（終了は可能だが同期が止まるだけ。再起動で復帰）
    private static let syncDaemons: [String: String] = [
        "fileproviderd": "iCloud/クラウドのファイル同期を行うプロセス",
        "bird": "iCloud Drive の同期を行うプロセス",
        "cloudd": "iCloud 全般の同期を行うプロセス",
        "nsurlsessiond": "バックグラウンドのダウンロード/同期を行うプロセス",
    ]

    /// セキュリティソフト（終了すると保護が一時的に無効化）
    private static let antivirusKeywords = ["K7", "Norton", "Avast", "Kaspersky", "McAfee",
                                            "Bitdefender", "ESET", "Sophos", "Malwarebytes", "ClamXAV"]

    /// プロセスを解説する
    static func explain(name: String, pid: Int32?) -> ProcessExplanation {
        let lower = name.lowercased()

        // 1. システム基幹 → 終了非推奨
        for (key, desc) in systemCritical where lower.contains(key.lowercased()) {
            return ProcessExplanation(
                whatItIs: desc,
                risk: .high,
                riskDetail: "macOS の動作に必須のプロセスです。終了すると画面表示・音声・ログインなどが停止し、強制再起動が必要になる恐れがあります。終了は推奨しません（高負荷は一時的なことが多く、放置すれば収まる場合があります）。",
                quitRecommended: false
            )
        }

        // 2. クラウド同期デーモン
        for (key, desc) in syncDaemons where lower.contains(key.lowercased()) {
            return ProcessExplanation(
                whatItIs: desc,
                risk: .medium,
                riskDetail: "終了しても致命的ではありませんが、進行中のクラウド同期が中断されます（通常は自動で再開します）。CPU 高負荷は大量ファイルの同期中であることが多く、同期完了まで待つのが安全です。",
                quitRecommended: false
            )
        }

        // 3. セキュリティソフト
        for key in antivirusKeywords where lower.contains(key.lowercased()) {
            return ProcessExplanation(
                whatItIs: "\(name)（セキュリティ対策ソフト）",
                risk: .high,
                riskDetail: "終了するとウイルス対策のリアルタイム保護が一時的に無効になります。CPU 負荷はスキャン中が原因のことが多いです。終了よりスキャン時間帯の変更や除外設定を推奨します。",
                quitRecommended: false
            )
        }

        // 4. ブラウザ/Electron 等のヘルパー
        if lower.contains("helper") || lower.contains("renderer") || lower.contains("(gpu)") {
            return ProcessExplanation(
                whatItIs: "\(name)（アプリの補助プロセス。多くはブラウザのタブや拡張機能、Electron アプリの一部）",
                risk: .medium,
                riskDetail: "終了すると、その補助プロセスが担当していたタブやウィンドウだけが落ちます。未保存の入力（フォーム等）があれば失われる可能性があります。親アプリ自体は通常残ります。",
                quitRecommended: true
            )
        }

        // 5. 開発ツール/ランタイム（作業中の可能性）
        let devKeywords = ["node", "python", "ruby", "java", "docker", "xcode", "claude", "code"]
        if devKeywords.contains(where: { lower.contains($0) }) {
            return ProcessExplanation(
                whatItIs: "\(name)（開発ツール/スクリプトのランタイム）",
                risk: .medium,
                riskDetail: "ビルドやスクリプトの実行中だと、終了によりその処理が中断されます。意図して動かしているものなら終了しないでください。",
                quitRecommended: true
            )
        }

        // 6. 起動中のユーザーアプリか？
        if let appName = runningRegularAppName(pid: pid, name: name) {
            return ProcessExplanation(
                whatItIs: "\(appName)（あなたが起動したアプリ）",
                risk: .medium,
                riskDetail: "終了すると未保存の作業内容が失われる可能性があります。保存してから終了するか、不要であれば終了して問題ありません。",
                quitRecommended: true
            )
        }

        // 7. 不明なプロセス
        return ProcessExplanation(
            whatItIs: "\(name)（詳細不明のバックグラウンドプロセス）",
            risk: .high,
            riskDetail: "用途を特定できませんでした。システムや常駐アプリの一部の可能性があり、不用意に終了すると予期せぬ不具合が出ることがあります。何か分からない場合は終了しないでください。",
            quitRecommended: false
        )
    }

    /// pid または名前が、起動中の通常アプリ（ユーザー向けアプリ）に一致すればその表示名を返す
    static func runningRegularAppName(pid: Int32?, name: String) -> String? {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let pid = pid, app.processIdentifier == pid { return app.localizedName ?? name }
            if app.localizedName == name { return app.localizedName }
            if app.executableURL?.lastPathComponent == name { return app.localizedName ?? name }
        }
        return nil
    }
}
