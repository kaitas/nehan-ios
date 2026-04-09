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

        let types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
        ]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    // MARK: - Sleep

    struct SleepSummary {
        let asleep: Date?
        let awake: Date?
        let totalMinutes: Int
        let deepMinutes: Int
        let remMinutes: Int
        let coreMinutes: Int
        let awakeMinutes: Int
    }

    func fetchSleepSummary(for date: Date) async throws -> SleepSummary? {
        guard isAvailable else { return nil }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        // 前日 20:00 〜 当日 12:00
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
        var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0

        for sample in samples {
            let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0

            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deep += minutes
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                rem += minutes
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                core += minutes
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awake += minutes
            default:
                core += minutes
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

        let totalSleep = deep + rem + core
        return SleepSummary(
            asleep: earliestAsleep,
            awake: latestAwake,
            totalMinutes: Int(totalSleep),
            deepMinutes: Int(deep),
            remMinutes: Int(rem),
            coreMinutes: Int(core),
            awakeMinutes: Int(awake)
        )
    }

    func fetchSleepData(for date: Date) async throws -> LogEntry? {
        guard let summary = try await fetchSleepSummary(for: date) else { return nil }

        let formatter = ISO8601DateFormatter()
        let totalHours = Double(summary.totalMinutes) / 60.0
        let payload: [String: Any] = [
            "asleep": summary.asleep.map { formatter.string(from: $0) } ?? "",
            "awake": summary.awake.map { formatter.string(from: $0) } ?? "",
            "totalHours": round(totalHours * 10) / 10,
            "stages": [
                ["stage": "deep", "minutes": summary.deepMinutes],
                ["stage": "rem", "minutes": summary.remMinutes],
                ["stage": "core", "minutes": summary.coreMinutes],
                ["stage": "awake", "minutes": summary.awakeMinutes],
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let jsonString = String(data: jsonData, encoding: .utf8)
        return LogEntry(type: .sleep, payload: jsonString)
    }

    // MARK: - Steps

    func fetchStepCount(for date: Date) async throws -> Int {
        guard isAvailable else { return 0 }

        let stepType = HKQuantityType(.stepCount)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let steps = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(query)
        }

        return Int(steps)
    }

    // MARK: - Heart Rate

    struct HeartRateSummary {
        let average: Int
        let min: Int
        let max: Int
        let resting: Int?
    }

    func fetchHeartRateSummary(for date: Date) async throws -> HeartRateSummary? {
        guard isAvailable else { return nil }

        let hrType = HKQuantityType(.heartRate)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let stats = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics?, Error>) in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax]
            ) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }

        guard let stats,
              let avg = stats.averageQuantity()?.doubleValue(for: unit) else { return nil }

        let min = stats.minimumQuantity()?.doubleValue(for: unit) ?? avg
        let max = stats.maximumQuantity()?.doubleValue(for: unit) ?? avg

        return HeartRateSummary(
            average: Int(avg),
            min: Int(min),
            max: Int(max),
            resting: nil
        )
    }

    // MARK: - Combined health log entry

    func fetchDailyHealthData(for date: Date) async throws -> LogEntry? {
        let steps = try await fetchStepCount(for: date)
        let hr = try await fetchHeartRateSummary(for: date)

        if steps == 0 && hr == nil { return nil }

        var payload: [String: Any] = ["steps": steps]
        if let hr {
            payload["heartRate"] = [
                "avg": hr.average,
                "min": hr.min,
                "max": hr.max,
            ]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let jsonString = String(data: jsonData, encoding: .utf8)
        return LogEntry(type: .memo, payload: "health: \(jsonString ?? "")")
    }
}
