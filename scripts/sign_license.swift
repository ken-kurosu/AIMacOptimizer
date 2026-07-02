#!/usr/bin/env swift
import Foundation
import CryptoKit

// AI Mac Optimizer — ライセンスキー発行ツール（署名付き・偽造不可）
//
// 使い方:
//   swift scripts/sign_license.swift            # 買い切り(Lifetime)キーを発行
//   swift scripts/sign_license.swift monthly    # 月額Proキーを発行
//
// 秘密鍵は ~/.aimac_license_private_key（base64, chmod 600）から読み込む。
// 出力されたキー（AIMAC-...）を購入者にメールで送る。
// アプリ側は埋め込んだ公開鍵でオフライン検証する（サーバー不要・コスト0）。

let tierArg = CommandLine.arguments.dropFirst().first ?? "lifetime"
let tierByte: UInt8 = (tierArg == "monthly" || tierArg == "pro") ? 1 : 2
let tierName = tierByte == 1 ? "Pro (Monthly)" : "Pro (Lifetime)"

let keyPath = ("~/.aimac_license_private_key" as NSString).expandingTildeInPath
guard let b64 = try? String(contentsOfFile: keyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let privData = Data(base64Encoded: b64),
      let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
    FileHandle.standardError.write(Data("❌ 秘密鍵が読めません: \(keyPath)\n".utf8))
    exit(1)
}

// v2 message = [version(2), tier(1), expiryHi, expiryLo, nonce(2)]
//   expiry = 2025-01-01(UTC) からの日数(UInt16)。0 = 無期限。月額(tier=1)は今日+35日。
let epoch = 1_735_689_600.0   // 2025-01-01 00:00:00 UTC
let expiryDays: Int = tierByte == 1
    ? Int((Date().timeIntervalSince1970 - epoch) / 86_400) + 35   // 月額: 35日後(更新の猶予込み)
    : 0                                                            // 買い切り: 無期限
var message = Data([2, tierByte, UInt8((expiryDays >> 8) & 0xff), UInt8(expiryDays & 0xff)])
message.append(Data((0..<2).map { _ in UInt8.random(in: 0...255) }))

let signature = try! priv.signature(for: message)
var keyData = message
keyData.append(signature)

let body = keyData.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")

print("プラン: \(tierName)")
print("ライセンスキー（この行を購入者に送る）:")
print("AIMAC-" + body)
