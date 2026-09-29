import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var multiCoordinatesText: String = ""
    @State private var optimizeShortestPath: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // 執行中控制區塊 (暫停/繼續/停止)
                if session.isSpoofing {
                    Section("Active Cruise Control") {
                        HStack(spacing: 12) {
                            if session.isPaused {
                                Button {
                                    session.resumeRoute()
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Button {
                                    session.pauseRoute()
                                } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                session.stopRoute(keepCurrentPosition: true)
                            } label: {
                                Label("Stop at Current", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // 多點座標巡航（免 GPX）
                Section("Multi-Point Coordinates Patrol") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste coordinates (one per line or separated by comma/semicolon):")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $multiCoordinatesText)
                            .frame(height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            .font(.caption.monospaced())

                        Toggle("Optimize Shortest Path (TSP)", isOn: $optimizeShortestPath)
                            .font(.subheadline)

                        Button {
                            parseAndStartMultiPoints()
                        } label: {
                            Label("Build & Start Patrol Route", systemImage: "map.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(multiCoordinatesText.isEmpty)
                    }
                }

                // 速度與模式調整
                Section("Travel Speed & Mode") {
                    Picker("Mode", selection: $session.travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if session.travelMode == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Custom Speed")
                                Spacer()
                                Text(String(format: "%.1f km/h", session.customSpeedKmh))
                                    .font(.callout.monospacedDigit())
                                    .bold()
                                    .foregroundStyle(.tint)
                            }
                            Slider(value: $session.customSpeedKmh, in: 1...150, step: 0.5)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 傳統兩點規劃與 GPX
                Section("Road route & GPX") {
                    Button("Use current pin as start") { start = session.simulated ?? session.pin }
                    Button("Use current pin as end") { end = session.pin }
                    
                    Button { onBuild() } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Build Point-to-Point Route", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)

                    Button(action: onPlay) { Label("Follow A-B Route", systemImage: "play.fill") }
                    Button(action: onImportGPX) { Label("Import GPX File", systemImage: "square.and.arrow.down") }
                    Button(action: onExportGPX) { Label("Export GPX File", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle("Routes & Patrol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // 解析文字中的多組座標，並可選按最短路徑（Greedy Nearest Neighbor）排序
    private func parseAndStartMultiPoints() {
        var parsed: [CLLocationCoordinate2D] = []
        let rawLines = multiCoordinatesText.components(separatedBy: CharacterSet(charactersIn: "\n;,;"))

        for line in rawLines {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
            if parts.count >= 2,
               let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                parsed.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }

        guard !parsed.isEmpty else { return }

        var finalRoute = parsed
        if optimizeShortestPath && parsed.count > 2 {
            finalRoute = computeShortestPath(parsed)
        }

        session.startRoute(finalRoute)
        dismiss()
    }

    // 最短路徑演算法 (Greedy Nearest Neighbor)
    private func computeShortestPath(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var unvisited = points
        var result: [CLLocationCoordinate2D] = []

        var current = unvisited.removeFirst()
        result.append(current)

        while !unvisited.isEmpty {
            let currentLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
            var nearestIndex = 0
            var minDistance = Double.greatestFiniteMagnitude

            for (index, pt) in unvisited.enumerated() {
                let dist = currentLoc.distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude))
                if dist < minDistance {
                    minDistance = dist
                    nearestIndex = index
                }
            }

            current = unvisited.remove(at: nearestIndex)
            result.append(current)
        }

        return result
    }
}
