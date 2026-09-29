import CoreLocation
import Foundation
import MapKit

// 1. 保留原本的 RouteBuilder（不用動它）
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
            throw NSError(domain: "Locus", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
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

// 2. 將原本的 GPXCodec 替換成以下內容（含 GPXXMLParser 備援類別）
enum GPXCodec {
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var coords: [CLLocationCoordinate2D] = []

        // 1. 正則匹配：同時相容雙引號 " 與單引號 '
        let pattern = #"(?:lat|lon)\s*=\s*["']([^"']+)["']\s*(?:lon|lat)\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges == 3,
                      let r1 = Range(match.range(at: 1), in: text),
                      let r2 = Range(match.range(at: 2), in: text) else { return }

                let fullMatchRange = Range(match.range, in: text)!
                let matchSnippet = String(text[fullMatchRange])
                if matchSnippet.lowercased().hasPrefix("lat") {
                    if let lat = Double(text[r1]), let lon = Double(text[r2]) {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                } else {
                    if let lon = Double(text[r1]), let lat = Double(text[r2]) {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                }
            }
        }

        // 2. 如果正則沒抓到，使用標準 XMLParser 備援機制解析
        if coords.isEmpty {
            let parser = GPXXMLParser(data: data)
            coords = parser.parse()
        }

        guard !coords.isEmpty else {
            throw NSError(domain: "Locus", code: 2, userInfo: [NSLocalizedDescriptionKey: "No track points found in GPX"])
        }
        return coords
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(name)</name>
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
}

// 備援 XML 解析器（貼在檔案最下方）
private class GPXXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var coords: [CLLocationCoordinate2D] = []

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> [CLLocationCoordinate2D] {
        parser.parse()
        return coords
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let tag = elementName.lowercased()
        if tag == "trkpt" || tag == "wpt" || tag == "rtept" {
            if let latStr = attributeDict["lat"] ?? attributeDict["LAT"],
               let lonStr = attributeDict["lon"] ?? attributeDict["LON"],
               let lat = Double(latStr),
               let lon = Double(lonStr) {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
    }
}
