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

    /// Whether storage deletion is allowed
    var canDeleteStorage: Bool { currentTier.isPro }

    /// Whether scheduled optimization is allowed
    var canUseSchedule: Bool { currentTier.isPro }

    /// Whether multi-language is allowed
    var canUseMultiLanguage: Bool { currentTier.isPro }

    /// Whether AI chat (Deep Diagnosis + Chat) is available
    /// Free: diagnosis only (3/week), Pro: unlimited diagnosis + chat
    var canUseDiagnosis: Bool {
        if currentTier.isPro { return true }
        return weeklyAISuggestionsUsed < 3
    }

    /// Whether AI chat consultation is available (Pro only)
    var canUseAIChat: Bool { currentTier.isPro }

    /// Whether AI suggestions are available (Free: 3/week limit)
    var canUseAISuggestions: Bool {
        if currentTier.isPro { return true }
        return weeklyAISuggestionsUsed < 3
    }

    /// Remaining AI suggestions for free tier
    var remainingAISuggestions: Int {
        if currentTier.isPro { return -1 } // unlimited
        return max(0, 3 - weeklyAISuggestionsUsed)
    }

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
        if let tierRaw = UserDefaults.standard.string(forKey: tierKey),
           let tier = LicenseTier(rawValue: tierRaw) {
            currentTier = tier
        }
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
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

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

        // Validate license key format: AIMAC-XXXX-XXXX-XXXX
        if validateLicenseKeyFormat(key) {
            // If server validation URL is configured, validate online
            if let validationURL = PurchaseConfig.licenseValidationURL {
                Task {
                    let isValid = await validateLicenseOnline(key: key, url: validationURL)
                    if isValid {
                        applyLicenseKey(key, tier: .proLifetime)
                    } else {
                        licenseKeyMessage = "無効なライセンスキーです。購入確認メールをご確認ください。"
                        licenseKeySuccess = false
                    }
                }
            } else {
                // Offline validation: accept valid format keys
                // Determine tier from key prefix
                let tier: LicenseTier = key.contains("LIFE") ? .proLifetime : .pro
                applyLicenseKey(key, tier: tier)
            }
        } else {
            licenseKeyMessage = "無効なキー形式です。形式: AIMAC-XXXX-XXXX-XXXX"
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
