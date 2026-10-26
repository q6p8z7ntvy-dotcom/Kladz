import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    var id: String { "\(latitude),\(longitude)" }
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static let maximumSavedPlaces = 100
    private static let maximumNameLength = 100

    static func load(key: String) -> [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            return []
        }

        // Preferences can be stale or malformed after upgrades. Never feed invalid
        // coordinates into MapKit or let an unexpectedly large list grow without bound.
        return decoded.compactMap { place in
            guard place.latitude.isFinite,
                  place.longitude.isFinite,
                  (-90.0...90.0).contains(place.latitude),
                  (-180.0...180.0).contains(place.longitude) else {
                return nil
            }
            let trimmed = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = String((trimmed.isEmpty ? "Saved place" : trimmed).prefix(maximumNameLength))
            return SavedPlace(name: safeName, latitude: place.latitude, longitude: place.longitude)
        }.prefix(maximumSavedPlaces).map { $0 }
    }

    static func save(_ places: [SavedPlace], key: String) {
        let safePlaces = places.prefix(maximumSavedPlaces).filter {
            $0.latitude.isFinite &&
            $0.longitude.isFinite &&
            (-90.0...90.0).contains($0.latitude) &&
            (-180.0...180.0).contains($0.longitude)
        }.map { place in
            let trimmed = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedPlace(
                name: String((trimmed.isEmpty ? "Saved place" : trimmed).prefix(maximumNameLength)),
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
        if let data = try? JSONEncoder().encode(safePlaces) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
