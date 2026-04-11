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

        var readTypes: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.mindfulSession),
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.toothbrushingEvent),
            HKCategoryType(.headache),
            HKCategoryType(.handwashingEvent),
        ]

        var writeTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.toothbrushingEvent),
            HKCategoryType(.headache),
            HKCategoryType(.handwashingEvent),
            HKCategoryType(.mindfulSession),
        ]

        // State of Mind (iOS 18+)
        if #available(iOS 18.0, *) {
            readTypes.insert(HKSampleType.stateOfMindType())
            writeTypes.insert(HKSampleType.stateOfMindType())
        }
        // Menstrual flow (optional, only if user is female)
        if UserProfileStore.shared.isFemale {
            readTypes.insert(HKCategoryType(.menstrualFlow))
        }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
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

    // MARK: - Naps (daytime sleep)

    struct NapSummary {
        let startTime: Date
        let endTime: Date
        let durationMinutes: Int

        /// Nap quality evaluation based on duration
        var evaluation: String {
            if durationMinutes <= 20 {
                return "パワーナップ（理想的）"
            } else if durationMinutes <= 30 {
                return "短い仮眠"
            } else if durationMinutes < 60 {
                return "やや長め（睡眠慣性に注意）"
            } else if durationMinutes >= 80 && durationMinutes <= 100 {
                return "1サイクル（徹夜明けに有効）"
            } else {
                return "長時間の昼寝"
            }
        }

        var evaluationEn: String {
            if durationMinutes <= 20 {
                return "Power nap (ideal)"
            } else if durationMinutes <= 30 {
                return "Short nap"
            } else if durationMinutes < 60 {
                return "Slightly long (sleep inertia risk)"
            } else if durationMinutes >= 80 && durationMinutes <= 100 {
                return "Full cycle (good after all-nighter)"
            } else {
                return "Long nap"
            }
        }
    }

    /// Fetch daytime naps (12:00-22:00) from HealthKit sleep analysis
    func fetchNaps(for date: Date) async throws -> [NapSummary] {
        guard isAvailable else { return [] }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        // Search window: 12:00-22:00 (daytime naps)
        let startOfSearch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let endOfSearch = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date)!

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

        // Filter actual sleep samples (not inBed or awake)
        let sleepSamples = samples.filter { sample in
            sample.value != HKCategoryValueSleepAnalysis.awake.rawValue &&
            sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue
        }

        guard !sleepSamples.isEmpty else { return [] }

        // Group contiguous sleep samples into nap sessions (gap > 10 min = new nap)
        var naps: [NapSummary] = []
        var sessionStart = sleepSamples[0].startDate
        var sessionEnd = sleepSamples[0].endDate

        for i in 1..<sleepSamples.count {
            let sample = sleepSamples[i]
            let gap = sample.startDate.timeIntervalSince(sessionEnd)

            if gap > 600 { // 10 minute gap = new nap session
                let duration = Int(sessionEnd.timeIntervalSince(sessionStart) / 60)
                if duration >= 5 { // Ignore micro-naps under 5 minutes
                    naps.append(NapSummary(startTime: sessionStart, endTime: sessionEnd, durationMinutes: duration))
                }
                sessionStart = sample.startDate
            }
            sessionEnd = max(sessionEnd, sample.endDate)
        }

        // Don't forget the last session
        let duration = Int(sessionEnd.timeIntervalSince(sessionStart) / 60)
        if duration >= 5 {
            naps.append(NapSummary(startTime: sessionStart, endTime: sessionEnd, durationMinutes: duration))
        }

        return naps
    }

    func fetchSleepData(for date: Date) async throws -> LogEntry? {
        guard let summary = try await fetchSleepSummary(for: date) else { return nil }

        let formatter = ISO8601DateFormatter()
        let totalHours = Double(summary.totalMinutes) / 60.0

        // Fetch naps for the same day
        let naps = (try? await fetchNaps(for: date)) ?? []
        let napsPayload: [[String: Any]] = naps.map { nap in
            [
                "start": formatter.string(from: nap.startTime),
                "end": formatter.string(from: nap.endTime),
                "minutes": nap.durationMinutes,
                "evaluation": nap.evaluation,
            ]
        }

        var payload: [String: Any] = [
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

        if !napsPayload.isEmpty {
            payload["naps"] = napsPayload
        }

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
        let hrv: Double?  // SDNN in ms
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

        // Fetch resting heart rate
        let restingHR: Int? = try await {
            let restingType = HKQuantityType(.restingHeartRate)
            let restingStats = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics?, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: restingType,
                    quantitySamplePredicate: predicate,
                    options: .discreteAverage
                ) { _, result, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: result)
                }
                store.execute(query)
            }
            guard let avg = restingStats?.averageQuantity()?.doubleValue(for: unit) else { return nil }
            return Int(avg)
        }()

        // Fetch HRV (SDNN)
        let hrv: Double? = try await {
            let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
            let hrvUnit = HKUnit.secondUnit(with: .milli)
            let hrvStats = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics?, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: hrvType,
                    quantitySamplePredicate: predicate,
                    options: .discreteAverage
                ) { _, result, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: result)
                }
                store.execute(query)
            }
            guard let avg = hrvStats?.averageQuantity()?.doubleValue(for: hrvUnit) else { return nil }
            return avg
        }()

        return HeartRateSummary(
            average: Int(avg),
            min: Int(min),
            max: Int(max),
            resting: restingHR,
            hrv: hrv
        )
    }

    // MARK: - Heart Rate Timeline

    struct HeartRatePoint {
        let time: Date
        let bpm: Int
    }

    /// Fetch individual heart rate samples for timeline visualization
    func fetchHeartRateTimeline(for date: Date) async throws -> [HeartRatePoint] {
        guard isAvailable else { return [] }

        let hrType = HKQuantityType(.heartRate)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }

        return samples.map { sample in
            HeartRatePoint(
                time: sample.startDate,
                bpm: Int(sample.quantity.doubleValue(for: unit))
            )
        }
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
            case .ashamed: "恥ずかしい"
            case .brave: "勇敢"
            case .calm: "穏やか"
            case .confident: "自信"
            case .content: "満足"
            case .disappointed: "失望"
            case .discouraged: "落胆"
            case .disgusted: "嫌悪"
            case .embarrassed: "恥ずかしい"
            case .excited: "興奮"
            case .frustrated: "苛立ち"
            case .grateful: "感謝"
            case .guilty: "罪悪感"
            case .happy: "幸せ"
            case .hopeless: "絶望"
            case .hopeful: "希望"
            case .indifferent: "無関心"
            case .irritated: "イライラ"
            case .jealous: "嫉妬"
            case .joyful: "喜び"
            case .lonely: "孤独"
            case .passionate: "情熱"
            case .peaceful: "平和"
            case .proud: "誇り"
            case .relieved: "安心"
            case .sad: "悲しい"
            case .scared: "恐怖"
            case .stressed: "ストレス"
            case .surprised: "驚き"
            case .worried: "心配"
            case .annoyed: "不快"
            case .drained: "疲弊"
            case .overwhelmed: "圧倒"
            case .satisfied: "満足"
            @unknown default: "—"
            }
        }

        return StateOfMindSummary(valence: valence, valenceLabel: emoji, labels: labelNames)
    }

    // MARK: - Write: State of Mind

    @available(iOS 18.0, *)
    func saveStateOfMind(valence: Double, labels: [HKStateOfMind.Label]) async throws {
        guard isAvailable else { return }

        let sample = HKStateOfMind(
            date: Date(),
            kind: .momentaryEmotion,
            valence: valence,
            labels: labels,
            associations: []
        )
        try await store.save(sample)
    }

    // MARK: - Write: Caffeine

    func saveCaffeine(mg: Double) async throws {
        guard isAvailable else { return }

        let type = HKQuantityType(.dietaryCaffeine)
        let quantity = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: mg)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
        try await store.save(sample)
    }

    // MARK: - Write: Water

    func saveWater(ml: Double) async throws {
        guard isAvailable else { return }

        let type = HKQuantityType(.dietaryWater)
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
        try await store.save(sample)
    }

    // MARK: - Write: Toothbrushing

    func saveToothbrushing(durationMinutes: Int = 3) async throws {
        guard isAvailable else { return }

        let type = HKCategoryType(.toothbrushingEvent)
        let end = Date()
        let start = end.addingTimeInterval(-Double(durationMinutes * 60))
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        try await store.save(sample)
    }

    // MARK: - Write: Headache

    func saveHeadache(severity: Int) async throws {
        guard isAvailable else { return }

        // severity: 0=not present, 1=mild, 2=moderate, 3=severe
        let type = HKCategoryType(.headache)
        let sample = HKCategorySample(type: type, value: severity, start: Date(), end: Date())
        try await store.save(sample)
    }

    // MARK: - Write: Handwashing

    func saveHandwashing(durationSeconds: Int = 20) async throws {
        guard isAvailable else { return }

        let type = HKCategoryType(.handwashingEvent)
        let end = Date()
        let start = end.addingTimeInterval(-Double(durationSeconds))
        let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        try await store.save(sample)
    }

    // MARK: - Read: Today's quick record counts

    func fetchTodayQuickRecordCounts() async throws -> QuickRecordCounts {
        guard isAvailable else { return QuickRecordCounts() }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let caffeine = fetchQuantitySum(type: .dietaryCaffeine, unit: .gramUnit(with: .milli), predicate: predicate)
        async let water = fetchQuantitySum(type: .dietaryWater, unit: .literUnit(with: .milli), predicate: predicate)
        async let toothbrush = fetchCategoryCount(type: .toothbrushingEvent, predicate: predicate)
        async let headache = fetchCategoryCount(type: .headache, predicate: predicate)
        async let handwash = fetchCategoryCount(type: .handwashingEvent, predicate: predicate)

        return QuickRecordCounts(
            caffeineMg: (try? await caffeine) ?? 0,
            waterMl: (try? await water) ?? 0,
            toothbrushCount: (try? await toothbrush) ?? 0,
            headacheCount: (try? await headache) ?? 0,
            handwashCount: (try? await handwash) ?? 0
        )
    }

    struct QuickRecordCounts {
        var caffeineMg: Double = 0
        var waterMl: Double = 0
        var toothbrushCount: Int = 0
        var headacheCount: Int = 0
        var handwashCount: Int = 0
    }

    private func fetchQuantitySum(type: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double {
        let quantityType = HKQuantityType(type)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            store.execute(query)
        }
    }

    private func fetchCategoryCount(type: HKCategoryTypeIdentifier, predicate: NSPredicate) async throws -> Int {
        let categoryType = HKCategoryType(type)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results?.count ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Combined health log entry

    func fetchDailyHealthData(for date: Date) async throws -> LogEntry? {
        let steps = try await fetchStepCount(for: date)
        let hr = try await fetchHeartRateSummary(for: date)

        if steps == 0 && hr == nil { return nil }

        var payload: [String: Any] = ["steps": steps]
        if let hr {
            var hrDict: [String: Any] = [
                "avg": hr.average,
                "min": hr.min,
                "max": hr.max,
            ]
            if let resting = hr.resting { hrDict["resting"] = resting }
            if let hrv = hr.hrv { hrDict["hrv"] = Int(hrv) }
            payload["heartRate"] = hrDict
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let jsonString = String(data: jsonData, encoding: .utf8)
        return LogEntry(type: .memo, payload: "health: \(jsonString ?? "")")
    }
}
