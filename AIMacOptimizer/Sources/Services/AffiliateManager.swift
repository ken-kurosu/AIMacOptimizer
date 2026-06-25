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
    // Replace URLs with actual affiliate links

    private let affiliateProducts: [AffiliateRecommendation] = [
        // Memory-related
        AffiliateRecommendation(
            title: "メモリ増設のすすめ",
            description: "RAMが常に80%超え → メモリ増設で根本解決",
            icon: "memorychip",
            affiliateURL: "https://amzn.to/your-ram-affiliate-link",
            category: .memory
        ),
        AffiliateRecommendation(
            title: "外付けSSD おすすめ",
            description: "ストレージ不足を外付けSSDで解消",
            icon: "externaldrive",
            affiliateURL: "https://amzn.to/your-ssd-affiliate-link",
            category: .storage
        ),
        AffiliateRecommendation(
            title: "iCloud+ 50GB プラン",
            description: "月額¥130でストレージ不足を解消",
            icon: "icloud",
            affiliateURL: "https://www.apple.com/icloud/",
            category: .storage
        ),
        // Performance
        AffiliateRecommendation(
            title: "MacBook Air M3 で快適に",
            description: "古いMacからの買い替えで劇的改善",
            icon: "laptopcomputer",
            affiliateURL: "https://amzn.to/your-macbook-affiliate-link",
            category: .performance
        ),
        AffiliateRecommendation(
            title: "USBハブ・ドッキングステーション",
            description: "周辺機器を整理して作業効率アップ",
            icon: "cable.connector",
            affiliateURL: "https://amzn.to/your-hub-affiliate-link",
            category: .performance
        ),
        // Security
        AffiliateRecommendation(
            title: "Time Machine 用 外付けHDD",
            description: "大事なデータのバックアップに",
            icon: "clock.arrow.circlepath",
            affiliateURL: "https://amzn.to/your-hdd-affiliate-link",
            category: .security
        ),
    ]

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
                $0.category == .storage && $0.title.contains("SSD")
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
