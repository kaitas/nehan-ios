import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    @Published var lastLocation: CLLocation?
    @Published var isTracking = false

    var onNewLocation: ((LogEntry) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        manager.startMonitoringSignificantLocationChanges()
        isTracking = true
    }

    func stopTracking() {
        manager.stopMonitoringSignificantLocationChanges()
        isTracking = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.lastLocation = location

            let placeName = await self.reverseGeocode(location)

            let entry = LogEntry(
                type: .location,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                placeName: placeName
            )
            self.onNewLocation?(entry)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[nehan] Location error: \(error.localizedDescription)")
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            if let item = mapItems.first {
                return item.address?.shortAddress ?? item.name
            }
        } catch {
            print("[nehan] Geocode error: \(error)")
        }
        return nil
    }
}
