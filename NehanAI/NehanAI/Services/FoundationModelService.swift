import Foundation
import FoundationModels

@available(iOS 26.0, *)
enum FoundationModelService {

    /// Generate a natural Japanese blog entry from health/location context
    static func generateBlog(context: BlogContext) async throws -> String {
        let session = LanguageModelSession()

        let prompt = buildPrompt(context: context)
        let response = try await session.respond(to: prompt)
        return response.content
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
        return lines.joined(separator: "\n")
    }
}
