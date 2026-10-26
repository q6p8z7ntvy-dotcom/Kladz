import CoreLocation
import Foundation
import MapKit

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "Kladz", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        return sample(polyline: route.polyline, every: 12)
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / meters)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                sampled.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return sampled
    }
}

enum GPXCodec {
    private static let maximumFileSize = 20 * 1_024 * 1_024
    private static let maximumPointCount = 100_000

    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Check the file size before reading it into memory.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > maximumFileSize {
            throw NSError(
                domain: "Kladz",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "GPX file is too large (maximum 20 MB)."]
            )
        }

        let data = try Data(contentsOf: url)
        guard data.count <= maximumFileSize,
              let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "Kladz",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "GPX must be a UTF-8 file smaller than 20 MB."]
            )
        }

        // Only read actual GPX waypoint/route/track points, not unrelated lat/lon
        // attributes such as metadata bounds. Lookaheads accept either attribute order.
        let pattern = #"<(?:trkpt|rtept|wpt)\b(?=[^>]*\blat="([^"]+)")(?=[^>]*\blon="([^"]+)")[^>]*>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var coords: [CLLocationCoordinate2D] = []
        var exceededPointLimit = false

        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let match,
                  let latRange = Range(match.range(at: 1), in: text),
                  let lonRange = Range(match.range(at: 2), in: text),
                  let latitude = Double(text[latRange]),
                  let longitude = Double(text[lonRange]),
                  latitude.isFinite,
                  longitude.isFinite,
                  (-90.0...90.0).contains(latitude),
                  (-180.0...180.0).contains(longitude) else { return }

            guard coords.count < maximumPointCount else {
                exceededPointLimit = true
                stop.pointee = true
                return
            }
            coords.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }

        guard !coords.isEmpty else {
            throw NSError(
                domain: "Kladz",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid GPX track, route, or waypoint points were found."]
            )
        }
        guard !exceededPointLimit else {
            throw NSError(
                domain: "Kladz",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "GPX contains too many points (maximum 100,000)."]
            )
        }
        return coords
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Kladz Route") -> String {
        let safeName = escapeXML(name)
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Kladz" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(safeName)</name>
            <trkseg>

        """
        for c in coordinates {
            body += String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>\n", c.latitude, c.longitude)
        }
        body += """
            </trkseg>
          </trk>
        </gpx>
        """
        return body
    }

    /// Escape reserved characters in XML text nodes so custom route names stay valid GPX.
    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
