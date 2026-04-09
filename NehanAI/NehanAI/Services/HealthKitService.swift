import Foundation
import HealthKit

class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestPermission() async throws {
        guard isAvailable else { return }

        let sleepType = HKCategoryType(.sleepAnalysis)
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func fetchSleepData(for date: Date) async throws -> LogEntry? {
        guard isAvailable else { return nil }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        let startOfSearch = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: date)!)!
        let endOfSearch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfSearch, end: endOfSearch, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        var earliestAsleep: Date?
        var latestAwake: Date?

        var deepMinutes = 0.0
        var remMinutes = 0.0
        var coreMinutes = 0.0
        var awakeMinutes = 0.0

        for sample in samples {
            let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0

            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepMinutes += minutes
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remMinutes += minutes
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                coreMinutes += minutes
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeMinutes += minutes
            default:
                coreMinutes += minutes
            }

            if sample.value != HKCategoryValueSleepAnalysis.awake.rawValue &&
               sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue {
                if earliestAsleep == nil || sample.startDate < earliestAsleep! {
                    earliestAsleep = sample.startDate
                }
                if latestAwake == nil || sample.endDate > latestAwake! {
                    latestAwake = sample.endDate
                }
            }
        }

        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "asleep": earliestAsleep.map { formatter.string(from: $0) } ?? "",
            "awake": latestAwake.map { formatter.string(from: $0) } ?? "",
            "stages": [
                ["stage": "deep", "minutes": Int(deepMinutes)],
                ["stage": "rem", "minutes": Int(remMinutes)],
                ["stage": "core", "minutes": Int(coreMinutes)],
                ["stage": "awake", "minutes": Int(awakeMinutes)],
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let jsonString = String(data: jsonData, encoding: .utf8)

        return LogEntry(type: .sleep, payload: jsonString)
    }
}
