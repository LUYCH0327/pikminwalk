import SwiftUI

struct JoystickPad: View {
    var onChange: (CGVector) -> Void

    @EnvironmentObject private var session: SpoofSession
    @State private var dragOffset: CGSize = .zero
    @State private var showSpeedControls = false
    private let radius: CGFloat = 52

    var body: some View {
        VStack(spacing: 12) {
            // 速度控制彈出面板
            if showSpeedControls {
                VStack(spacing: 8) {
                    HStack {
                        Picker("Mode", selection: $session.travelMode) {
                            ForEach(TravelMode.allCases) { mode in
                                Image(systemName: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if session.travelMode == .custom {
                        HStack {
                            Text(String(format: "%.1f km/h", session.customSpeedKmh))
                                .font(.caption.monospacedDigit())
                                .bold()
                                .foregroundStyle(LocusTheme.accent)

                            Slider(value: $session.customSpeedKmh, in: 1...150, step: 0.5)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 4)
                .frame(width: 220)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 搖桿主體 + 速度開關按鈕
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .frame(width: radius * 2 + 28, height: radius * 2 + 28)
                        .locusGlass(.clear, in: Circle())

                    Circle()
                        .stroke(LocusTheme.accent.opacity(0.4), lineWidth: 2)
                        .frame(width: radius * 2, height: radius * 2)

                    Circle()
                        .fill(LocusTheme.accent)
                        .frame(width: 44, height: 44)
                        .shadow(color: LocusTheme.accent.opacity(0.45), radius: 8)
                        .offset(dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let limited = clamp(value.translation, radius: radius)
                                    dragOffset = limited
                                    onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        dragOffset = .zero
                                    }
                                    onChange(.zero)
                                }
                        )
                }

                // 點擊切換顯示/隱藏速度選單的小按鈕
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSpeedControls.toggle()
                    }
                } label: {
                    Image(systemName: "gauge.high")
                        .font(.caption)
                        .padding(6)
                        .background(LocusTheme.accent, in: Circle())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel("Movement joystick")
    }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
