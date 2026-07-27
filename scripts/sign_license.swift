#!/usr/bin/env swift
import Foundation
import CryptoKit

// AI Mac Optimizer — ライセンスキー発行ツール（署名付き・偽造不可）
//
// 使い方:
//   swift scripts/sign_license.swift              # 買い切り(Lifetime・無期限)。友人/チーム/身内の招待に。
//   swift scripts/sign_license.swift monthly      # 月額Pro(今日+35日)
//   swift scripts/sign_license.swift beta [日数]  # ベータ招待(Pro・既定90日。例: beta 60)
//
// 秘密鍵は ~/.aimac_license_private_key（base64, chmod 600）から読み込む。
// 出力されたキー（AIMAC-...）を招待相手/購入者に送る。
// アプリ側は埋め込んだ公開鍵でオフライン検証する（サーバー不要・コスト0）。
// ※ 旧「固定プロモコード(AIMAC-FRIENDS-2026等)」は build16 で廃止。招待は本スクリプトの署名キーで行う。

let epoch = 1_735_689_600.0   // 2025-01-01 00:00:00 UTC
let todayDays = Int((Date().timeIntervalSince1970 - epoch) / 86_400)

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "lifetime"
let tierByte: UInt8
let expiryDays: Int
let tierName: String
switch mode {
case "monthly", "pro":
    tierByte = 1; expiryDays = todayDays + 35; tierName = "Pro (Monthly・35日)"
case "beta":
    tierByte = 1
    let days = args.count > 1 ? (Int(args[1]) ?? 90) : 90
    expiryDays = todayDays + days; tierName = "Pro (Beta・\(days)日)"
default:
    tierByte = 2; expiryDays = 0; tierName = "Pro (Lifetime・無期限)"
}

let keyPath = ("~/.aimac_license_private_key" as NSString).expandingTildeInPath
guard let b64 = try? String(contentsOfFile: keyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let privData = Data(base64Encoded: b64),
      let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
    FileHandle.standardError.write(Data("❌ 秘密鍵が読めません: \(keyPath)\n".utf8))
    exit(1)
}

// v2 message = [version(2), tier(1), expiryHi, expiryLo, nonce(2)]
//   expiry = 2025-01-01(UTC) からの日数(UInt16)。0 = 無期限。（tier/expiry は上の switch で決定済み）
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
