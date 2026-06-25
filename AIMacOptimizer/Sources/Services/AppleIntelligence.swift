import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple のオンデバイス LLM（Foundation Models / Apple Intelligence）への薄いラッパー。
/// 無料・完全ローカル・キー不要。対応 OS / チップ（Apple Silicon + 対応 macOS）でのみ動作する。
///
/// FoundationModels を import できないツールチェーン/OS では `isAvailable == false` となり、
/// 呼び出し側は LocalAdvisor へフォールバックする。
enum AppleIntelligence {

    /// 実行環境でオンデバイス LLM が利用可能か
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    /// オンデバイス LLM に応答させる。利用不可なら nil（呼び出し側でフォールバック）。
    static func respond(system: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(instructions: system)
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return nil
            }
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }
}
