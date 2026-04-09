import Foundation
import Combine
import CoreLocation

struct PlaceBookmark: Codable, Identifiable {
    let id: UUID
    var name: String
    let latitude: Double
    let longitude: Double
    var isSecret: Bool

    init(name: String, latitude: Double, longitude: Double, isSecret: Bool = false) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isSecret = isSecret
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

    /// 座標から200m以内のブックマークを返す
    func match(latitude: Double, longitude: Double, threshold: Double = 200) -> PlaceBookmark? {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return bookmarks
            .filter { $0.distance(to: coord) <= threshold }
            .min { $0.distance(to: coord) < $1.distance(to: coord) }
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
