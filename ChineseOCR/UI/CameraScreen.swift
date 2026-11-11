import SwiftUI

struct CameraScreen: View {
    let camera: CameraController
    let isProcessing: Bool
    let onCapture: () -> Void

    @State private var showMenu = false
    @State private var pinchStartZoom: CGFloat?

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
                menuButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)

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

            if showMenu {
                MenuView { setMenu(open: false) }
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
    }

    private func setMenu(open: Bool) {
        withAnimation(.smooth(duration: 0.3)) { showMenu = open }
    }

    private var menuButton: some View {
        Button { setMenu(open: true) } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Menu")
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
