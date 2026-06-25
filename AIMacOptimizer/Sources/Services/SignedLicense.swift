import Foundation
import CryptoKit

/// 署名付きライセンスキーの検証。
/// 公開鍵をアプリに埋め込み、オフラインで Ed25519 署名を検証する。
/// 秘密鍵を持つ発行者（運営）が署名したキーのみ有効になり、
/// 「形式だけ合わせた偽造キー」は弾かれる（＝課金の壁が成立する）。
///
/// キー形式: "AIMAC-" + base64url( message(6byte) + signature(64byte) )
///   message = [version(1), tier(1: 1=Pro / 2=Lifetime), nonce(4)]
/// 発行は scripts/sign_license.swift で行う（秘密鍵は ~/.aimac_license_private_key）。
enum SignedLicense {
    /// 発行者の Ed25519 公開鍵（base64）。秘密鍵はアプリに含めない。
    private static let publicKeyB64 = "YcPnCKIi/O0OsWbN5xp8bZyFQoe2x9abeR9UuOfffB8="

    /// キーを検証し、有効なら付与すべき tier を返す。無効なら nil。
    static func verify(_ key: String) -> LicenseTier? {
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

        // message[1] = tier
        switch message[message.startIndex + 1] {
        case 1: return .pro
        case 2: return .proLifetime
        default: return nil
        }
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
