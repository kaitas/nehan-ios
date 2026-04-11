import Foundation
import Combine
import CoreLocation

struct PlaceBookmark: Codable, Identifiable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    var isSecret: Bool
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

    init(name: String, latitude: Double, longitude: Double, isSecret: Bool = false, category: Category = .other) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isSecret = isSecret
        self.category = category
        self.createdAt = Date()
        self.lastVisitedAt = nil
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: there)
    }
}

class PlaceBookmarkStore: ObservableObject {
    static let shared = PlaceBookmarkStore()

    private let key = "ai.nehan.placeBookmarks"
    @Published var bookmarks: [PlaceBookmark] = []

    init() {
        load()
    }

    func add(_ bookmark: PlaceBookmark) {
        bookmarks.append(bookmark)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func update(_ bookmark: PlaceBookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[i] = bookmark
            save()
        }
    }

    /// 座標から200m以内のブックマー��を返す（読み取り専用、view bodyから安全に呼べる）
    func match(latitude: Double, longitude: Double, threshold: Double = 200) -> PlaceBookmark? {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return bookmarks
            .filter({ $0.distance(to: coord) <= threshold })
            .min(by: { $0.distance(to: coord) < $1.distance(to: coord) })
    }

    /// 座標から200m以内のブック��ークの lastVisitedAt を更新���view body外から呼ぶ）
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
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlaceBookmark].self, from: data) else { return }
        bookmarks = decoded
    }
}
