import Foundation

/// Contextual affiliate recommendation based on user's system state
struct AffiliateRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let affiliateURL: String
    let category: AffiliateCategory
}

enum AffiliateCategory: String {
    case memory = "メモリ"
    case storage = "ストレージ"
    case performance = "パフォーマンス"
    case security = "セキュリティ"
}

/// Manages contextual affiliate recommendations shown to Free tier users
final class AffiliateManager {
    static let shared = AffiliateManager()
    private init() {}

    // MARK: - Affiliate Product Database
    /// Amazon アソシエイト トラッキングID（クリック後24時間内の購入が成果対象。カート投入は90日）
    static let amazonTag = "kurosu02-22"

    /// アプリの言語設定に対応する Amazon の表示言語コード。
    /// タグは amazon.co.jp 専用のためストアは固定し、表示言語だけ language= で切り替える。
    static func amazonLanguageParam() -> String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        switch raw {
        case "ja": return "ja_JP"
        case "en": return "en_US"
        case "zh": return "zh_CN"
        default:
            // system: 端末の言語が日本語なら日本語、それ以外は英語
            let code = Locale.preferredLanguages.first ?? "en"
            return code.hasPrefix("ja") ? "ja_JP" : "en_US"
        }
    }

    /// Amazon.co.jp の検索URLに、アフィリエイトタグ＋アプリ言語に合わせた表示言語を付与
    static func amazonSearch(_ encodedQuery: String) -> String {
        "https://www.amazon.co.jp/s?k=\(encodedQuery)&tag=\(amazonTag)&language=\(amazonLanguageParam())"
    }

    // 言語設定を反映するため computed（アクセスのたびに現在の言語でURLを生成）
    private var affiliateProducts: [AffiliateRecommendation] {[
        // Memory-related（Apple Silicon は増設不可のため、外付けSSDでSwap負荷を軽減する方向で誘導）
        AffiliateRecommendation(
            title: "メモリ不足を軽くする方法",
            description: "RAMが常に高い → 外付けSSD活用や周辺環境の見直しで改善",
            icon: "memorychip",
            affiliateURL: AffiliateManager.amazonSearch("Mac%20%E5%91%A8%E8%BE%BA%E6%A9%9F%E5%99%A8"),
            category: .memory
        ),
        AffiliateRecommendation(
            title: "ストレージ容量を増やす方法",
            description: "空き容量を根本的に増やすなら外付けSSDが手軽（写真・動画・古い資料を退避）",
            icon: "externaldrive",
            // 「外付けSSD」で検索（広めに誘導してクリック率を上げる）
            affiliateURL: AffiliateManager.amazonSearch("%E5%A4%96%E4%BB%98%E3%81%91SSD"),
            category: .storage
        ),
        AffiliateRecommendation(
            title: "iCloud+ 50GB プラン",
            description: "月額¥130でクラウドに退避（外付けが不要な人向け）",
            icon: "icloud",
            affiliateURL: "https://www.apple.com/icloud/",
            category: .storage
        ),
        // Performance
        AffiliateRecommendation(
            title: "MacBook の買い替えで快適に",
            description: "古いMacからの買い替えで劇的改善",
            icon: "laptopcomputer",
            affiliateURL: AffiliateManager.amazonSearch("MacBook%20Air"),
            category: .performance
        ),
        AffiliateRecommendation(
            title: "USBハブ・ドッキングステーション",
            description: "周辺機器を整理して作業効率アップ",
            icon: "cable.connector",
            affiliateURL: AffiliateManager.amazonSearch("USB-C%20%E3%83%8F%E3%83%96"),
            category: .performance
        ),
        // Security
        AffiliateRecommendation(
            title: "Time Machine 用 外付けHDD",
            description: "大事なデータのバックアップに",
            icon: "clock.arrow.circlepath",
            affiliateURL: AffiliateManager.amazonSearch("%E5%A4%96%E4%BB%98%E3%81%91HDD"),
            category: .security
        ),
    ]}

    // MARK: - Contextual Selection

    /// Returns up to 2 contextual affiliate recommendations based on system state
    func getRecommendations(
        memoryUsagePercent: Double,
        storageFreeGB: Double,
        storageTotalGB: Double
    ) -> [AffiliateRecommendation] {
        var recommendations: [AffiliateRecommendation] = []

        // High memory usage → recommend RAM upgrade or new Mac
        if memoryUsagePercent > 80 {
            if let ram = affiliateProducts.first(where: { $0.category == .memory }) {
                recommendations.append(ram)
            }
        }

        // Low storage → recommend external SSD or iCloud
        let storageUsagePercent = storageTotalGB > 0
            ? ((storageTotalGB - storageFreeGB) / storageTotalGB) * 100
            : 0
        if storageUsagePercent > 75 {
            if let storage = affiliateProducts.first(where: {
                // SSD商品はtitleに"SSD"を含まない場合があるためdescriptionも見る（以前は到達不能だった）
                $0.category == .storage && ($0.title.contains("SSD") || $0.description.contains("SSD"))
            }) {
                recommendations.append(storage)
            }
        } else if storageUsagePercent > 60 {
            if let icloud = affiliateProducts.first(where: {
                $0.category == .storage && $0.title.contains("iCloud")
            }) {
                recommendations.append(icloud)
            }
        }

        // If no contextual match, show general recommendation
        if recommendations.isEmpty {
            if let backup = affiliateProducts.first(where: { $0.category == .security }) {
                recommendations.append(backup)
            }
        }

        // Always max 2 recommendations
        return Array(recommendations.prefix(2))
    }

    /// Track affiliate click for analytics (future: send to analytics backend)
    func trackClick(recommendation: AffiliateRecommendation) {
        let defaults = UserDefaults.standard
        let key = "affiliate_clicks_\(recommendation.category.rawValue)"
        let count = defaults.integer(forKey: key)
        defaults.set(count + 1, forKey: key)
        print("[Affiliate] Click tracked: \(recommendation.title)")
    }
}
