import SwiftUI

struct RootView: View {
    @State private var camera = CameraController()
    private let dictionary = ChineseDictionary.shared
    @State private var result: OCRResult?
    @State private var isProcessing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Stays mounted under the result so closing it doesn't rebuild the
            // preview layer and reattach it to the session.
            CameraScreen(camera: camera, isProcessing: isProcessing, onCapture: capture)
                .allowsHitTesting(result == nil)
                .accessibilityHidden(result != nil)

            if let result {
                ResultView(result: result, dictionary: dictionary) {
                    camera.start()
                    withAnimation(.smooth(duration: 0.3)) { self.result = nil }
                }
                .id(result.id)
                .transition(.opacity)
            }
        }
        .overlay {
            // iOS saves a screenshot of the app for the app switcher when it leaves
            // the foreground; covering the UI keeps the photo out of that snapshot.
            if scenePhase != .active {
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            camera.start()
            await dictionary.ensureLoaded()
        }
    }

    private func capture() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            guard let image = await camera.capturePhoto() else { return }
            let recognized = await TextRecognizer.recognize(in: image, dictionary: dictionary)
            camera.stop()
            withAnimation(.smooth(duration: 0.35)) { result = recognized }
        }
    }
}
