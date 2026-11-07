import SwiftUI
import Translation

struct ResultView: View {
    let result: OCRResult
    let dictionary: ChineseDictionary
    let onDismiss: () -> Void

    @State private var selected: OCRWord?
    @State private var translator = SentenceTranslator()
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                FrozenFrame(result: result, selected: $selected)
                    .frame(height: proxy.size.height * 0.58)

                InfoPanel(
                    result: result,
                    dictionary: dictionary,
                    translator: translator,
                    selected: $selected
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 8)
            .accessibilityLabel("Scan again")
        }
        .sensoryFeedback(.selection, trigger: selected)
        .translationTask(translationConfig) { session in
            await translator.run(sentences: result.sentences, using: session)
        }
        .onAppear {
            guard result.hasChinese else { return }
            translationConfig = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: "en")
            )
        }
    }
}

// MARK: - Frozen frame with tappable words

/// The photo is zoomed with a render transform, while word markers are drawn in a
/// single unscaled `Canvas` and hit-tested manually. One view per word made every
/// pinch frame re-render hundreds of views.
private struct FrozenFrame: View {
    let result: OCRResult
    @Binding var selected: OCRWord?

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pinchStart: (scale: CGFloat, offset: CGSize)?
    @State private var lastPanTranslation: CGSize?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let maxScale: CGFloat = 6
    /// Smallest on-screen marker and tap area, in points, for tiny words.
    private let minMarker: CGFloat = 14
    private let minTapTarget: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fitted = fittedRect(container: size, image: result.image.size)

            ZStack {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .opacity(0.72)
                    .scaleEffect(scale)
                    .offset(offset)

                Canvas { context, canvasSize in
                    let bounds = CGRect(origin: .zero, size: canvasSize)
                    for word in result.words {
                        let rect = screenRect(for: word, fitted: fitted, size: size)
                        guard rect.intersects(bounds) else { continue }
                        draw(word, in: rect, context: &context)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(zoomGesture(in: size).simultaneously(with: panGesture(in: size)))
            .onTapGesture { location in
                guard let word = word(at: location, fitted: fitted, size: size) else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    selected = (selected == word) ? nil : word
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    if voiceOverEnabled {
                        ForEach(result.words) { word in
                            let rect = screenRect(for: word, fitted: fitted, size: size)
                            Rectangle()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .accessibilityLabel(word.text)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { selected = (selected == word) ? nil : word }
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .clipped()
        .background(Color.black)
    }

    private func draw(_ word: OCRWord, in rect: CGRect, context: inout GraphicsContext) {
        let isSelected = selected == word
        let marker = rect.insetBy(dx: min(0, (rect.width - minMarker) / 2),
                                  dy: min(0, (rect.height - minMarker) / 2))
        if isSelected {
            context.fill(Path(roundedRect: marker, cornerRadius: 4, style: .continuous),
                         with: .color(Theme.accent.opacity(0.35)))
        }
        let thickness: CGFloat = isSelected ? 2.5 : 1.5
        let underline = CGRect(x: marker.minX + 2.5, y: marker.maxY + 3 - thickness,
                               width: max(marker.width - 5, 1), height: thickness)
        context.fill(Path(roundedRect: underline, cornerRadius: thickness / 2),
                     with: .color(isSelected ? Theme.accent : Color.white.opacity(0.7)))
    }

    /// Prefers a word whose box contains the point; otherwise the nearest word
    /// whose enlarged tap area does, so tiny words stay easy to hit.
    private func word(at point: CGPoint, fitted: CGRect, size: CGSize) -> OCRWord? {
        var nearest: (word: OCRWord, distance: CGFloat)?
        for word in result.words {
            let rect = screenRect(for: word, fitted: fitted, size: size)
            if rect.contains(point) { return word }
            let target = rect.insetBy(dx: min(0, (rect.width - minTapTarget) / 2),
                                      dy: min(0, (rect.height - minTapTarget) / 2))
            guard target.contains(point) else { continue }
            let distance = hypot(point.x - rect.midX, point.y - rect.midY)
            if distance < nearest?.distance ?? .infinity { nearest = (word, distance) }
        }
        return nearest?.word
    }

    /// A word's rect on screen after the current zoom (about the center) and pan.
    private func screenRect(for word: OCRWord, fitted: CGRect, size: CGSize) -> CGRect {
        let rect = viewRect(for: word.boundingBox, in: fitted)
        return CGRect(
            x: size.width / 2 + (rect.minX - size.width / 2) * scale + offset.width,
            y: size.height / 2 + (rect.minY - size.height / 2) * scale + offset.height,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Zooms toward the point where the pinch began, keeping it under the fingers.
    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (scale, offset)
                pinchStart = start
                let newScale = min(max(start.scale * value.magnification, 1), maxScale)
                let ratio = newScale / start.scale
                let anchorX = value.startLocation.x - size.width / 2
                let anchorY = value.startLocation.y - size.height / 2
                scale = newScale
                offset = clamped(
                    CGSize(width: anchorX - (anchorX - start.offset.width) * ratio,
                           height: anchorY - (anchorY - start.offset.height) * ratio),
                    in: size
                )
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Applies drag deltas rather than the total translation, so panning picks up
    /// smoothly after a pinch (which owns the offset while it's active).
    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let last = lastPanTranslation ?? .zero
                lastPanTranslation = value.translation
                guard scale > 1, pinchStart == nil else { return }
                offset = clamped(
                    CGSize(width: offset.width + value.translation.width - last.width,
                           height: offset.height + value.translation.height - last.height),
                    in: size
                )
            }
            .onEnded { _ in lastPanTranslation = nil }
    }

    /// Keeps the zoomed content covering the frame (no panning past its edges).
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2
        let maxY = (scale - 1) * size.height / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func fittedRect(container: CGSize, image: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Vision boxes are normalized with a bottom-left origin.
    private func viewRect(for box: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + box.minX * fitted.width,
            y: fitted.minY + (1 - box.maxY) * fitted.height,
            width: box.width * fitted.width,
            height: box.height * fitted.height
        )
    }
}

// MARK: - Bottom panel

private struct InfoPanel: View {
    let result: OCRResult
    let dictionary: ChineseDictionary
    let translator: SentenceTranslator
    @Binding var selected: OCRWord?

    var body: some View {
        ScrollView {
            Group {
                if !result.hasChinese {
                    emptyState
                } else if let selected {
                    WordDetail(word: selected.text, entries: dictionary.entries(for: selected.text))
                        .id(selected.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    SentenceList(sentences: result.sentences, translator: translator)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color(white: 0.07))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Chinese found")
                .font(.title3.weight(.semibold))
            Text("Move closer, steady the phone, and make sure the text is well lit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SentenceList: View {
    let sentences: [String]
    let translator: SentenceTranslator

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Tap a word")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.tertiary)

            ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                VStack(alignment: .leading, spacing: 8) {
                    Text(sentence)
                        .font(Theme.Font.hanzi(22))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    translationLine(for: sentence)
                }
            }
        }
    }

    @ViewBuilder
    private func translationLine(for sentence: String) -> some View {
        if let english = translator.translation(for: sentence) {
            Text(english)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            switch translator.state {
            case .unavailable:
                Text("Translation unavailable")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            default:
                Text("Translating…")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
