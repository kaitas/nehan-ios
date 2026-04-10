import Foundation
import Observation

struct UserProfile: Codable {
    var birthYear: Int
    var birthMonth: Int
    var birthDay: Int
    var biologicalSex: BiologicalSex
    var language: AppLanguage
    var termsAccepted: Bool
    var termsAcceptedDate: Date?
    var privacyRead: Bool
    var termsRead: Bool
    var onboardingCompleted: Bool
    var displayName: String
    var recordPlaceNames: Bool
    var blogPublishHour: Int
    var currentStreak: Int
    var lastBlogDate: String?

    enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
        case male
        case female
        case other
        case preferNotToSay

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .male: String(localized: "sex_male", defaultValue: "男性")
            case .female: String(localized: "sex_female", defaultValue: "女性")
            case .other: String(localized: "sex_other", defaultValue: "その他")
            case .preferNotToSay: String(localized: "sex_prefer_not", defaultValue: "回答しない")
            }
        }

        var emoji: String {
            switch self {
            case .male: "♂"
            case .female: "♀"
            case .other: "⚧"
            case .preferNotToSay: "—"
            }
        }
    }

    enum AppLanguage: String, Codable, CaseIterable, Identifiable {
        case ja
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ja: "日本語"
            case .en: "English"
            case .zhHans: "简体中文"
            case .zhHant: "繁體中文"
            }
        }

        var flag: String {
            switch self {
            case .ja: "🇯🇵"
            case .en: "🇺🇸"
            case .zhHans: "🇨🇳"
            case .zhHant: "🇹🇼"
            }
        }
    }

    var birthday: DateComponents {
        DateComponents(year: birthYear, month: birthMonth, day: birthDay)
    }

    static let `default` = UserProfile(
        birthYear: 2000,
        birthMonth: 1,
        birthDay: 1,
        biologicalSex: .preferNotToSay,
        language: .ja,
        termsAccepted: false,
        termsAcceptedDate: nil,
        privacyRead: false,
        termsRead: false,
        onboardingCompleted: false,
        displayName: "",
        recordPlaceNames: true,
        blogPublishHour: 20,
        currentStreak: 0,
        lastBlogDate: nil
    )
}

@Observable
class UserProfileStore {
    static let shared = UserProfileStore()

    var profile: UserProfile

    private let key = "nehan_user_profile"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = saved
        } else {
            self.profile = .default
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func completeOnboarding() {
        profile.termsAccepted = true
        profile.termsAcceptedDate = Date()
        profile.onboardingCompleted = true
        save()
    }

    var needsOnboarding: Bool {
        !profile.onboardingCompleted
    }

    var isFemale: Bool {
        profile.biologicalSex == .female
    }

    var age: Int {
        Calendar.current.component(.year, from: Date()) - profile.birthYear
    }

    var isBirthdayToday: Bool {
        let now = Calendar.current.dateComponents([.month, .day], from: Date())
        return now.month == profile.birthMonth && now.day == profile.birthDay
    }

    func recordBlogPost() {
        let today = Self.todayString
        if profile.lastBlogDate == Self.yesterdayString || profile.lastBlogDate == nil {
            profile.currentStreak += 1
        } else if profile.lastBlogDate != today {
            profile.currentStreak = 1
        }
        profile.lastBlogDate = today
        save()
    }

    private static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.string(from: Date())
    }

    private static var yesterdayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }
}
