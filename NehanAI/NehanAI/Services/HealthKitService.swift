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

        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKCategoryType(.mindfulSession),
        ]
        // State of Mind (iOS 18+)
        if #available(iOS 18.0, *) {
            types.insert(HKSampleType.stateOfMindType())
        }
        // Menstrual flow (optional, only if user is female)
        if UserProfileStore.shared.isFemale {
            types.insert(HKCategoryType(.menstrualFlow))
        }
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

    // MARK: - Menstrual Cycle

    struct MenstrualSummary {
        let isOnPeriod: Bool
        let flowLevel: FlowLevel
        let daysSinceLastPeriod: Int?

        enum FlowLevel: String {
            case none, light, medium, heavy
            var emoji: String {
                switch self {
                case .none: "—"
                case .light: "🩸"
                case .medium: "🩸🩸"
                case .heavy: "🩸🩸🩸"
                }
            }
        }
    }

    func fetchMenstrualSummary(for date: Date) async throws -> MenstrualSummary? {
        guard isAvailable else { return nil }

        let menstrualType = HKCategoryType(.menstrualFlow)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -45, to: date)!
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: menstrualType,
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

        // Check today
        let todayStart = calendar.startOfDay(for: date)
        let todaySamples = samples.filter { calendar.isDate($0.startDate, inSameDayAs: todayStart) }

        if let todaySample = todaySamples.first {
            let flow: MenstrualSummary.FlowLevel = switch todaySample.value {
            case HKCategoryValueVaginalBleeding.light.rawValue: .light
            case HKCategoryValueVaginalBleeding.medium.rawValue: .medium
            case HKCategoryValueVaginalBleeding.heavy.rawValue: .heavy
            default: .light
            }
            return MenstrualSummary(isOnPeriod: true, flowLevel: flow, daysSinceLastPeriod: 0)
        }

        // Find most recent period
        if let mostRecent = samples.first {
            let days = calendar.dateComponents([.day], from: mostRecent.startDate, to: date).day
            return MenstrualSummary(isOnPeriod: false, flowLevel: .none, daysSinceLastPeriod: days)
        }

        return nil
    }

    // MARK: - Mindfulness

    struct MindfulSummary {
        let totalMinutes: Int
        let sessionCount: Int
    }

    func fetchMindfulSummary(for date: Date) async throws -> MindfulSummary? {
        guard isAvailable else { return nil }

        let mindfulType = HKCategoryType(.mindfulSession)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        let totalMinutes = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
        return MindfulSummary(totalMinutes: Int(totalMinutes), sessionCount: samples.count)
    }

    // MARK: - State of Mind (iOS 18+)

    struct StateOfMindSummary {
        let valence: Double          // -1.0 (very unpleasant) to 1.0 (very pleasant)
        let valenceLabel: String     // emoji representation
        let labels: [String]         // feeling labels
    }

    @available(iOS 18.0, *)
    func fetchStateOfMind(for date: Date) async throws -> StateOfMindSummary? {
        guard isAvailable else { return nil }

        let somType = HKSampleType.stateOfMindType()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(
                sampleType: somType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }

        guard let latest = samples.first as? HKStateOfMind else { return nil }

        let valence = latest.valence
        let emoji: String
        if valence > 0.5 { emoji = "😊" }
        else if valence > 0.0 { emoji = "🙂" }
        else if valence > -0.5 { emoji = "😐" }
        else { emoji = "😞" }

        let labelNames = latest.labels.map { label -> String in
            switch label {
            case .amazed: "驚き"
            case .amused: "楽しい"
            case .angry: "怒り"
            case .anxious: "不安"
            case .brave: "勇敢"
            case .calm: "穏やか"
            case .confident: "自信"
            case .content: "満足"
            case .disappointed: "失望"
            case .drained: "疲弊"
            case .excited: "興奮"
            case .grateful: "感謝"
            case .happy: "幸せ"
            case .hopeful: "希望"
            case .indifferent: "無関心"
            case .irritated: "イライラ"
            case .joyful: "喜び"
            case .lonely: "孤独"
            case .overwhelmed: "圧倒"
            case .peaceful: "平和"
            case .proud: "誇り"
            case .relieved: "安心"
            case .sad: "悲しい"
            case .stressed: "ストレス"
            case .worried: "心配"
            @unknown default: "—"
            }
        }

        return StateOfMindSummary(valence: valence, valenceLabel: emoji, labels: labelNames)
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
