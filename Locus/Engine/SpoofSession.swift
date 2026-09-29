import CoreLocation
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, cycle, drive, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk (~4 km/h)"
        case .cycle: return "Cycle (~15 km/h)"
        case .drive: return "Drive (~40 km/h)"
        case .custom: return "Custom Speed"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .drive: return "car.fill"
        case .custom: return "speedometer"
        }
    }

    var baseSpeedMps: Double {
        switch self {
        case .walk: return 1.2
        case .cycle: return 4.2
        case .drive: return 11.0
        case .custom: return 1.2
        }
    }
}

final class SpoofSession: ObservableObject {
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var isSpoofing = false
    @Published var isPaused = false

    @Published var travelMode: TravelMode = .walk
    @Published var customSpeedKmh: Double = 10.0

    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentRouteIndex: Int = 0

    private var moveTimer: Timer?

    var currentSpeedMps: Double {
        if travelMode == .custom {
            return customSpeedKmh / 3.6
        }
        return travelMode.baseSpeedMps
    }

    func setPin(_ coord: CLLocationCoordinate2D) {
        pin = coord
        if !isSpoofing {
            simulated = coord
        }
    }

    func startRoute(_ coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        stopRoute(keepCurrentPosition: true)
        
        routeCoordinates = coords
        currentRouteIndex = 0
        simulated = coords[0]
        isSpoofing = true
        isPaused = false

        scheduleNextStep()
    }

    func pauseRoute() {
        isPaused = true
        moveTimer?.invalidate()
        moveTimer = nil
    }

    func resumeRoute() {
        guard isSpoofing, isPaused else { return }
        isPaused = false
        scheduleNextStep()
    }

    func stopRoute(keepCurrentPosition: Bool = true) {
        moveTimer?.invalidate()
        moveTimer = nil
        isPaused = false
        isSpoofing = false

        if keepCurrentPosition, let current = simulated {
            pin = current
        }
        routeCoordinates.removeAll()
        currentRouteIndex = 0
    }

    private func scheduleNextStep() {
        guard isSpoofing, !isPaused, currentRouteIndex < routeCoordinates.count - 1 else {
            if currentRouteIndex >= routeCoordinates.count - 1 {
                stopRoute(keepCurrentPosition: true)
            }
            return
        }

        let from = routeCoordinates[currentRouteIndex]
        let to = routeCoordinates[currentRouteIndex + 1]

        let locA = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let locB = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distance = locA.distance(from: locB)

        let speed = currentSpeedMps * Double.random(in: 0.9...1.1)
        let duration = max(0.5, distance / speed)

        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self, self.isSpoofing, !self.isPaused else { return }
            self.currentRouteIndex += 1
            self.simulated = to
            self.scheduleNextStep()
        }
    }

    func moveJoystick(vector: CGVector) {
        guard vector != .zero else { return }
        let current = simulated ?? pin ?? CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        
        let speed = currentSpeedMps
        let deltaLat = (vector.dy * speed * 0.00001)
        let deltaLng = (vector.dx * speed * 0.00001)

        let newCoord = CLLocationCoordinate2D(
            latitude: current.latitude - deltaLat,
            longitude: current.longitude + deltaLng
        )

        simulated = newCoord
        pin = newCoord
        isSpoofing = true
    }
}
