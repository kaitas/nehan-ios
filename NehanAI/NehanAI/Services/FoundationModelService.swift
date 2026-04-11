import Foundation
import FoundationModels

@available(iOS 26.0, *)
enum FoundationModelService {

    /// Whether on-device Foundation Models (Apple Intelligence) are available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Generate a short text response from a free-form prompt.
    /// Returns empty string when Apple Intelligence is unavailable.
    static func generate(prompt: String) async throws -> String {
        guard isAvailable else { return "" }
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// Generate a natural Japanese blog entry from health/location context.
    /// Falls back to a template-based summary when Apple Intelligence is not supported.
    static func generateBlog(context: BlogContext) async throws -> String {
        guard isAvailable else {
            return buildFallbackText(context: context)
        }

        let session = LanguageModelSession()
        let prompt = buildPrompt(context: context)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Fallback (template-based)

    /// Produce a simple template summary when the LLM is unavailable.
    private static func buildFallbackText(context: BlogContext) -> String {
        var parts: [String] = []

        parts.append("\(context.date)の記録。")

        if let h = context.sleepHours {
            let quality = context.sleepQuality ?? ""
            parts.append("睡眠は\(String(format: "%.1f", h))時間\(quality.isEmpty ? "" : "（\(quality)）")。")
        }
        if let s = context.stepCount {
            parts.append("歩数は\(s)歩。")
        }
        if let hr = context.heartRate {
            parts.append("平均心拍は\(hr)bpm。")
        }
        if !context.places.isEmpty {
            parts.append("\(context.places.joined(separator: "、"))を訪問。")
        }
        if let d = context.dreamDiary, !d.isEmpty {
            parts.append("夢日記: \(d)")
        }
        if let f = context.feeling, !f.isEmpty {
            parts.append("気持ち: \(f)")
        }

        return parts.joined(separator: "")
    }

    struct BlogContext {
        var date: String
        var weather: String?
        var sleepHours: Double?
        var sleepQuality: String?
        var stepCount: Int?
        var heartRate: Int?
        var places: [String]
        var dreamDiary: String?
        var feeling: String?
        var leftover: String?
        var displayName: String?
    }

    private static func buildPrompt(context: BlogContext) -> String {
        var lines: [String] = []
        lines.append("あなたはライフログアプリ「nehan.ai」のブログライターです。")
        lines.append("以下のデータをもとに、自然な日本語で短い日記ブログ（200字以内）を書いてください。")
        lines.append("絵文字は控えめに。段落分けは不要。")
        lines.append("")
        lines.append("日付: \(context.date)")
        if let w = context.weather { lines.append("天気: \(w)") }
        if let h = context.sleepHours {
            lines.append("睡眠: \(String(format: "%.1f", h))時間 \(context.sleepQuality ?? "")")
        }
        if let s = context.stepCount { lines.append("歩数: \(s)歩") }
        if let hr = context.heartRate { lines.append("心拍: 平均\(hr)bpm") }
        if !context.places.isEmpty { lines.append("訪問場所: \(context.places.joined(separator: "、"))") }
        if let d = context.dreamDiary, !d.isEmpty { lines.append("夢日記: \(d)") }
        if let f = context.feeling, !f.isEmpty { lines.append("今日の気持ち: \(f)") }
        if let l = context.leftover, !l.isEmpty { lines.append("やり残したこと: \(l)") }
        return lines.joined(separator: "\n")
    }
}
