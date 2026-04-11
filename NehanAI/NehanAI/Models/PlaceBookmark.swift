import Foundation
import Combine
import CoreLocation

/// My座標タグ — GPS座標をタグIDで管理し、プライバシーを保護
struct PlaceTag: Codable, Identifiable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    /// true: GPS座標を小数点3桁（約110m精度）に丸めてサーバーに送信
    var roundCoordinates: Bool
    var category: Category
    var createdAt: Date
    var lastVisitedAt: Date?

    enum Category: String, Codable, CaseIterable, Identifiable {
        case home = "自宅"
        case work = "職場"
        case desk = "自席"
        case bedroom = "寝室"
        case other = "その他"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .work: "building.2.fill"
            case .desk: "desktopcomputer"
            case .bedroom: "bed.double.fill"
            case .other: "mappin"
            }
        }
    }

    init(name: String, latitude: Double, longitude: Double, roundCoordinates: Bool = true, category: Category = .other) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.roundCoordinates = roundCoordinates
        self.category = category
        self.createdAt = Date()
        self.lastVisitedAt = nil
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: there)
    }

    /// Round coordinate to 3 decimal places (~110m precision)
    static func round3(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}

// Backward-compatible type alias
typealias PlaceBookmark = PlaceTag

class PlaceTagStore: ObservableObject {
    static let shared = PlaceTagStore()

    private let key = "ai.nehan.placeBookmarks"
    private let migratedKey = "ai.nehan.placeTagMigrated"
    @Published var bookmarks: [PlaceTag] = []

    init() {
        load()
    }

    func add(_ bookmark: PlaceTag) {
        bookmarks.append(bookmark)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func update(_ bookmark: PlaceTag) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
            save()
        }
    }

    /// 座標から200m以内のタグを返す（読み取り専用、view bodyから安全に呼べる）
    func match(latitude: Double, longitude: Double, threshold: Double = 200) -> PlaceTag? {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return bookmarks
            .filter({ $0.distance(to: coord) <= threshold })
            .min(by: { $0.distance(to: coord) < $1.distance(to: coord) })
    }

    /// 座標から200m以内のタグの lastVisitedAt を更新（view body外から呼ぶ）
    func updateLastVisited(latitude: Double, longitude: Double, threshold: Double = 200) {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard let closest = bookmarks
            .filter({ $0.distance(to: coord) <= threshold })
            .min(by: { $0.distance(to: coord) < $1.distance(to: coord) })
        else { return }

        if let i = bookmarks.firstIndex(where: { $0.id == closest.id }) {
            bookmarks[i].lastVisitedAt = Date()
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }

        // Try new format first
        if let decoded = try? JSONDecoder().decode([PlaceTag].self, from: data) {
            bookmarks = decoded
            // Auto-migrate: if any bookmark still has roundCoordinates=false from old isSecret=false
            if !UserDefaults.standard.bool(forKey: migratedKey) {
                migrateToSafeDefaults()
            }
            return
        }

        // Legacy format migration: isSecret → roundCoordinates
        // Old PlaceBookmark had isSecret:Bool, new PlaceTag has roundCoordinates:Bool
        // Since the field name changed, old data decodes with roundCoordinates=false (default)
        // We migrate all to roundCoordinates=true (safe default)
        if let legacy = try? JSONDecoder().decode([LegacyPlaceBookmark].self, from: data) {
            bookmarks = legacy.map { old in
                PlaceTag.migrated(from: old, roundCoordinates: true)
            }
            save()
            UserDefaults.standard.set(true, forKey: migratedKey)
            print("[nehan] Migrated \(bookmarks.count) PlaceBookmarks → PlaceTags (roundCoordinates=true)")
        }
    }

    private func migrateToSafeDefaults() {
        var changed = false
        for i in bookmarks.indices {
            if !bookmarks[i].roundCoordinates {
                bookmarks[i].roundCoordinates = true
                changed = true
            }
        }
        if changed {
            save()
            print("[nehan] Migrated existing tags to roundCoordinates=true")
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}

// Backward-compatible type alias
typealias PlaceBookmarkStore = PlaceTagStore

// Legacy struct for migration only
private struct LegacyPlaceBookmark: Codable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    var isSecret: Bool
    var category: PlaceTag.Category
    var createdAt: Date
    var lastVisitedAt: Date?
}

private extension PlaceTag {
    static func migrated(from old: LegacyPlaceBookmark, roundCoordinates: Bool) -> PlaceTag {
        // UUID is generated fresh — acceptable for migration since tag IDs are local-only
        PlaceTag(
            name: old.name,
            latitude: old.latitude,
            longitude: old.longitude,
            roundCoordinates: roundCoordinates,
            category: old.category
        )
    }
}
