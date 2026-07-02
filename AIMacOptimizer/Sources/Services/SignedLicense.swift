import Foundation
import CryptoKit

/// 署名付きライセンスキーの検証。
/// 公開鍵をアプリに埋め込み、オフラインで Ed25519 署名を検証する。
/// 秘密鍵を持つ発行者（運営）が署名したキーのみ有効になり、
/// 「形式だけ合わせた偽造キー」は弾かれる（＝課金の壁が成立する）。
///
/// キー形式: "AIMAC-" + base64url( message(6byte) + signature(64byte) )
///   v1: message = [version=1, tier(1: 1=Pro / 2=Lifetime), nonce(4)]           … 期限なし
///   v2: message = [version=2, tier, expiryHi, expiryLo, nonce(2)]              … expiry付き
///       expiry = 2025-01-01(UTC) からの日数(UInt16)。0 = 無期限（買い切り等）。
/// 発行は scripts/sign_license.swift で行う（秘密鍵は ~/.aimac_license_private_key）。
enum SignedLicense {
    /// 発行者の Ed25519 公開鍵（base64）。秘密鍵はアプリに含めない。
    private static let publicKeyB64 = "cSchrIh/X8uvTti+YuUImtML+hk6j4DJKpMfpt56QrY="

    /// 有効期限日数の基準（2025-01-01 00:00:00 UTC の Unix 秒）
    private static let epoch: TimeInterval = 1_735_689_600

    /// 検証済みライセンス情報
    struct Verified {
        let tier: LicenseTier
        /// 有効期限（月額など）。nil = 無期限。
        let expiry: Date?
        /// 期限切れか（無期限は常に false）
        var isExpired: Bool {
            guard let expiry else { return false }
            return Date() > expiry
        }
    }

    /// キーの署名を検証して tier / expiry を返す。署名が不正なら nil。
    /// （期限切れ判定は呼び出し側で isExpired を見る）
    static func verify(_ key: String) -> Verified? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("AIMAC-") else { return nil }
        let body = String(trimmed.dropFirst("AIMAC-".count))
        guard let data = Data(base64urlEncoded: body), data.count == 70 else { return nil }

        let message = data.prefix(6)
        let signature = data.suffix(64)
        guard let pubData = Data(base64Encoded: publicKeyB64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
              pub.isValidSignature(signature, for: message) else {
            return nil
        }

        let m = Array(message)   // 0-based で扱う
        let tier: LicenseTier
        switch m[1] {
        case 1: tier = .pro
        case 2: tier = .proLifetime
        default: return nil
        }

        // v2 以降は expiry を読む（0 は無期限）
        var expiry: Date? = nil
        if m[0] >= 2 {
            let days = Int(m[2]) << 8 | Int(m[3])
            if days > 0 {
                expiry = Date(timeIntervalSince1970: epoch + Double(days) * 86_400)
            }
        }
        return Verified(tier: tier, expiry: expiry)
    }
}

extension Data {
    /// base64url（-_、パディングなし）からデコード
    init?(base64urlEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        guard let d = Data(base64Encoded: b) else { return nil }
        self = d
    }
}
