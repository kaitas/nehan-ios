import Foundation

enum AppConfig {
    static let workerURL: String = {
        if let url = Bundle.main.object(forInfoDictionaryKey: "WORKER_URL") as? String,
           !url.isEmpty, !url.hasPrefix("$(") {
            return url
        }
        return "https://ios.nehan.ai"
    }()

    /// Legacy shared API token — use AuthService.shared.apiKey instead for per-user auth
    static let apiToken: String = {
        if let token = Bundle.main.object(forInfoDictionaryKey: "API_TOKEN") as? String,
           !token.isEmpty, !token.hasPrefix("$(") {
            return token
        }
        return ""
    }()

    static let syncIntervalMinutes: Double = 30
    static let batchSize = 50
}
