import Foundation

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: LogType
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var payload: String?
    var synced: Bool

    enum LogType: String, Codable {
        case location
        case sleep
        case memo
    }

    init(type: LogType, latitude: Double? = nil, longitude: Double? = nil, placeName: String? = nil, payload: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.payload = payload
        self.synced = false
    }
}

struct LogBatch: Codable {
    let entries: [LogEntryAPI]
}

struct LogEntryAPI: Codable {
    let timestamp: String
    let type: String
    var latitude: Double?
    var longitude: Double?
    var place_name: String?
    var payload: String?
}

extension LogEntry {
    func toAPI() -> LogEntryAPI {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return LogEntryAPI(
            timestamp: formatter.string(from: timestamp),
            type: type.rawValue,
            latitude: latitude,
            longitude: longitude,
            place_name: placeName,
            payload: payload
        )
    }
}
