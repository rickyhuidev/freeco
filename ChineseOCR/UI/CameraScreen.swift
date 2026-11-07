import SwiftUI

struct CameraScreen: View {
    let camera: CameraController
    let isProcessing: Bool
    let onCapture: () -> Void

    @State private var showAttribution = false
    @State private var pinchStartZoom: CGFloat?
    @State private var isPoop = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = pinchStartZoom ?? camera.zoomFactor
                            pinchStartZoom = start
                            camera.setZoom(start * value.magnification)
                        }
                        .onEnded { _ in pinchStartZoom = nil }
                )

            statusMessage

            VStack {
                HStack {
                    Spacer()
                    infoButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                if abs(camera.zoomFactor - 1) > 0.05 {
                    Button { camera.setZoom(1) } label: {
                        Text(String(format: "%.1f×", camera.zoomFactor))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("Reset zoom")
                    .padding(.bottom, 14)
                    .transition(.opacity)
                }

                ShutterButton(isBusy: isProcessing, action: onCapture)
                    .disabled(camera.status != .running)
                    .opacity(camera.status == .running ? 1 : 0.3)
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showAttribution) {
            AttributionView()
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    /// Tap opens the attributions; triple tap toggles the easter egg. Gestures
    /// instead of a Button, since a Button would fire on the first of three taps.
    private var infoButton: some View {
        ZStack {
            if isPoop {
                Text("💩")
                    .font(.system(size: 17))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 32, height: 32)
        .background(.ultraThinMaterial, in: Circle())
        .contentShape(Circle())
        .gesture(
            TapGesture(count: 3)
                .onEnded { withAnimation(.spring(duration: 0.35, bounce: 0.5)) { isPoop.toggle() } }
                .exclusively(before: TapGesture().onEnded { showAttribution = true })
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isPoop)
        .accessibilityElement()
        .accessibilityLabel("About and attributions")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showAttribution = true }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch camera.status {
        case .denied:
            hint("Camera access is off", detail: "Enable it in Settings › Freeco.")
        case .unavailable:
            hint("No camera", detail: "Run on an iPhone to scan text.")
        default:
            EmptyView()
        }
    }

    private func hint(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }
}

private struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 74, height: 74)
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(ShutterPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isBusy)
        .accessibilityLabel("Scan text")
    }
}

private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
