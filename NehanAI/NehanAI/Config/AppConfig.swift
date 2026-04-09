import Foundation

enum AppConfig {
    static let workerURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "WORKER_URL") as? String ?? "https://ios.nehan.ai"
    }()

    static let apiToken: String = {
        Bundle.main.object(forInfoDictionaryKey: "API_TOKEN") as? String ?? ""
    }()

    static let syncIntervalMinutes: Double = 30
    static let batchSize = 50
}
