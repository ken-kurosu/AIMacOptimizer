import Foundation
import SwiftUI
import Combine

/// License tier for the app
enum LicenseTier: String, Codable {
    case free = "free"
    case pro = "pro"
    case proLifetime = "pro_lifetime"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .proLifetime: return "Pro (Lifetime)"
        }
    }

    var isPro: Bool {
        self == .pro || self == .proLifetime
    }
}

/// Payment / purchase configuration
struct PurchaseConfig {
    // MARK: - Stripe Payment Link URLs
    // Stripe ダッシュボード > Products > Payment Links で生成した URL を設定
    // TODO: Stripe アカウント作成後に実際の Payment Link URL に差し替え
    static let proMonthlyURL = "https://buy.stripe.com/4gMeV6bN6fS61hv6XqgYU00"
    static let proLifetimeURL = "https://buy.stripe.com/00w9AMbN65dsbW90z2gYU01"

    // MARK: - License validation endpoint (optional: server-side validation)
    // 初期リリースはオフライン検証。将来的に Stripe Webhook + サーバーで自動発行に移行
    static let licenseValidationURL: String? = nil

    // MARK: - Pricing Display
    static let proMonthlyPrice = "¥480/月"
    static let proLifetimePrice = "¥4,980（買い切り）"
}

/// Manages license state, promo codes, purchase flow, and feature gating
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Published State
    @Published var currentTier: LicenseTier = .free
    @Published var promoCodeInput: String = ""
    @Published var promoCodeMessage: String = ""
    @Published var promoCodeSuccess: Bool = false
    @Published var licenseKeyInput: String = ""
    @Published var licenseKeyMessage: String = ""
    @Published var licenseKeySuccess: Bool = false

    // MARK: - Feature Gating
    /// AI suggestions used this week (Free: max 3/week)
    @Published var weeklyAISuggestionsUsed: Int = 0

    // MARK: - Feature Gating（v1方針）
    // Pro の価値は「ストレージのファイル削除」と「スケジュール自動最適化」に集約。
    // それ以外（メモリ最適化提案・診断・ローカルAI相談・言語切替）は全て Free で無制限。
    // （有料APIモードは廃止済み。以前の「AI提案 週3回」制限は funnel を損ねるため撤廃）

    /// Whether storage file deletion is allowed（Pro限定）
    var canDeleteStorage: Bool { currentTier.isPro }

    /// Whether scheduled auto-optimization is allowed（Pro限定）
    var canUseSchedule: Bool { currentTier.isPro }

    /// 言語切替は全ユーザー可（多言語対応は基本機能）
    var canUseMultiLanguage: Bool { true }

    /// 診断は全ユーザー無制限
    var canUseDiagnosis: Bool { true }

    /// AI相談（ローカル/オンデバイス）は全ユーザー可
    var canUseAIChat: Bool { true }

    /// メモリ最適化提案は全ユーザー無制限
    var canUseAISuggestions: Bool { true }

    /// -1 = 無制限
    var remainingAISuggestions: Int { -1 }

    // MARK: - Persistence Keys
    private let tierKey = "license_tier"
    private let promoCodeKey = "activated_promo_code"
    private let licenseKeyKey = "activated_license_key"
    private let weeklyCountKey = "weekly_ai_count"
    private let weekStartKey = "weekly_ai_week_start"

    // MARK: - Valid Promo Codes
    // In production, these would be server-validated. For now, local codes.
    private let validPromoCodes: [String: LicenseTier] = [
        "AIMAC-FRIENDS-2026": .proLifetime,    // 身内用：永久Pro
        "AIMAC-TEAM-PRO": .proLifetime,         // チームメンバー用
        "AIMAC-BETA-TESTER": .pro,              // ベータテスター用（Pro）
        "AIMAC-LAUNCH-SPECIAL": .proLifetime,   // ローンチキャンペーン
    ]

    // MARK: - Init
    private init() {
        loadState()
        resetWeeklyCountIfNeeded()
    }

    // MARK: - State Management
    private func loadState() {
        // tier は保存された license_tier 文字列を鵜呑みにせず、保存済みの
        // 署名キー/プロモコードを毎回再検証して導出する。
        // （tier 文字列を信用すると `defaults write <bundleID> license_tier pro_lifetime`
        //   だけで永久Pro化できてしまうため。署名検証はオフラインで偽造不可）
        var derived: LicenseTier = .free
        if let key = UserDefaults.standard.string(forKey: licenseKeyKey),
           let v = SignedLicense.verify(key), !v.isExpired {
            // 月額など期限付きキーは、期限切れなら自動的に Free へ戻る
            derived = v.tier
        } else if let code = UserDefaults.standard.string(forKey: promoCodeKey),
                  let tier = validPromoCodes[code] {
            derived = tier
        }
        currentTier = derived
        weeklyAISuggestionsUsed = UserDefaults.standard.integer(forKey: weeklyCountKey)
    }

    private func saveState() {
        UserDefaults.standard.set(currentTier.rawValue, forKey: tierKey)
        UserDefaults.standard.set(weeklyAISuggestionsUsed, forKey: weeklyCountKey)
    }

    /// Reset weekly counter if a new week has started
    private func resetWeeklyCountIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        if let weekStartData = UserDefaults.standard.object(forKey: weekStartKey) as? Date {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekStartData)?.start ?? weekStartData
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            if currentWeekStart > weekStart {
                weeklyAISuggestionsUsed = 0
                UserDefaults.standard.set(now, forKey: weekStartKey)
                saveState()
            }
        } else {
            UserDefaults.standard.set(now, forKey: weekStartKey)
        }
    }

    // MARK: - AI Suggestion Tracking
    /// Record that the user used an AI suggestion session
    func recordAISuggestionUse() {
        guard !currentTier.isPro else { return }
        weeklyAISuggestionsUsed += 1
        saveState()
    }

    // MARK: - Purchase Flow

    /// Stripe チェックアウトページを開く（Pro Monthly）
    func purchaseProMonthly() {
        guard let url = URL(string: PurchaseConfig.proMonthlyURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Stripe チェックアウトページを開く（Pro Lifetime）
    func purchaseProLifetime() {
        guard let url = URL(string: PurchaseConfig.proLifetimeURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - License Key Activation

    /// Activate a license key received after purchase
    func activateLicenseKey() {
        // 署名付きキーは base64url（大文字小文字を区別）のため uppercased しない
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty else {
            licenseKeyMessage = "ライセンスキーを入力してください"
            licenseKeySuccess = false
            return
        }

        // Check if already activated with this key
        if let existingKey = UserDefaults.standard.string(forKey: licenseKeyKey),
           existingKey == key {
            licenseKeyMessage = "このキーは既に適用済みです"
            licenseKeySuccess = false
            return
        }

        // 署名付きライセンスキーを検証（秘密鍵を持つ発行者が署名したキーのみ有効＝偽造不可・オフライン検証）
        if let v = SignedLicense.verify(key) {
            if v.isExpired {
                licenseKeyMessage = "このライセンスキーは有効期限が切れています。月額プランは更新後にお送りする新しいキーをご利用ください。"
                licenseKeySuccess = false
            } else {
                applyLicenseKey(key, tier: v.tier)
            }
        } else {
            licenseKeyMessage = "無効なライセンスキーです。購入確認メールのキーをそのまま貼り付けてください。"
            licenseKeySuccess = false
        }
    }

    /// Validate license key format
    private func validateLicenseKeyFormat(_ key: String) -> Bool {
        // Format: AIMAC-XXXX-XXXX-XXXX (alphanumeric groups)
        let pattern = "^AIMAC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    /// Validate license key against server
    private func validateLicenseOnline(key: String, url: String) async -> Bool {
        guard let requestURL = URL(string: url) else { return false }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["license_key": key, "machine_id": machineID()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return false }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let valid = json["valid"] as? Bool {
                return valid
            }
        } catch {
            print("[License] Online validation failed: \(error)")
        }
        return false
    }

    /// Get a unique machine identifier for license binding
    private func machineID() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        if let serialData = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String {
            return serialData
        }
        return UUID().uuidString
    }

    /// Apply a validated license key
    private func applyLicenseKey(_ key: String, tier: LicenseTier) {
        currentTier = tier
        UserDefaults.standard.set(key, forKey: licenseKeyKey)
        saveState()
        licenseKeyMessage = "\(tier.displayName) にアップグレードしました！"
        licenseKeySuccess = true
        licenseKeyInput = ""
    }

    // MARK: - Promo Code Activation
    func activatePromoCode() {
        let code = promoCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !code.isEmpty else {
            promoCodeMessage = "コードを入力してください"
            promoCodeSuccess = false
            return
        }

        // Check if already activated
        if let existingCode = UserDefaults.standard.string(forKey: promoCodeKey),
           existingCode == code {
            promoCodeMessage = "このコードは既に適用済みです"
            promoCodeSuccess = false
            return
        }

        // Validate code
        if let tier = validPromoCodes[code] {
            currentTier = tier
            UserDefaults.standard.set(code, forKey: promoCodeKey)
            saveState()
            promoCodeMessage = "\(tier.displayName) にアップグレードしました！"
            promoCodeSuccess = true
            promoCodeInput = ""
        } else {
            promoCodeMessage = "無効なプロモコードです"
            promoCodeSuccess = false
        }
    }

    // MARK: - Manual Tier Override (for testing)
    func setTier(_ tier: LicenseTier) {
        currentTier = tier
        saveState()
    }

    /// Reset to free tier
    func resetLicense() {
        currentTier = .free
        weeklyAISuggestionsUsed = 0
        UserDefaults.standard.removeObject(forKey: promoCodeKey)
        UserDefaults.standard.removeObject(forKey: licenseKeyKey)
        saveState()
    }
}
