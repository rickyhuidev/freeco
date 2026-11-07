import SwiftUI
import Translation

struct ResultView: View {
    let result: OCRResult
    let dictionary: ChineseDictionary
    let onDismiss: () -> Void

    @State private var selected: OCRWord?
    /// Keeps the sheet's content in place while it animates away after deselection.
    @State private var lastSelected: OCRWord?
    @State private var translator = SentenceTranslator()
    @State private var translationConfig: TranslationSession.Configuration?
    @Environment(\.scenePhase) private var scenePhase

    /// Sheet height as a fraction of the screen; the photo stays usable above it.
    private let sheetFraction: CGFloat = 0.45

    var body: some View {
        GeometryReader { proxy in
            // The photo runs edge to edge, so measure in full-screen coordinates.
            let safeArea = proxy.safeAreaInsets
            let screenHeight = proxy.size.height + safeArea.top + safeArea.bottom

            FrozenFrame(
                result: result,
                selected: $selected,
                // Below the close button: 8 pt padding + 36 pt button + 8 pt margin.
                topInset: safeArea.top + 52,
                bottomInset: selected == nil ? 0 : screenHeight * sheetFraction
            )
            .ignoresSafeArea()
            .overlay {
                if !result.hasChinese { noChinese }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            InfoPanel(result: result, dictionary: dictionary, translator: translator,
                      word: selected ?? lastSelected)
                .presentationDetents([.fraction(sheetFraction), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(sheetFraction)))
                .presentationBackground(Color(white: 0.07))
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
                // Sheets sit above RootView's privacy cover, so they need their own.
                .overlay {
                    if scenePhase != .active { Color.black.ignoresSafeArea() }
                }
        }
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
        .onChange(of: selected) { if let selected { lastSelected = selected } }
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

    private var noChinese: some View {
        VStack(spacing: 6) {
            Text("No Chinese found")
                .font(.headline)
            Text("Move closer, steady the phone, and make sure the text is well lit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(32)
    }
}

// MARK: - Frozen frame with tappable words

/// The photo is zoomed with a render transform, while word markers are drawn in a
/// single unscaled `Canvas` and hit-tested manually. One view per word made every
/// pinch frame re-render hundreds of views.
private struct FrozenFrame: View {
    let result: OCRResult
    @Binding var selected: OCRWord?
    /// Space at the top taken by the status area and close button.
    let topInset: CGFloat
    /// Height of the info panel covering the bottom of the frame (0 when hidden).
    /// The photo may pan up by this much so words under the panel can be seen.
    let bottomInset: CGFloat

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
            let photo = filledRect(in: size)

            ZStack {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .opacity(0.72)
                    .scaleEffect(scale)
                    .offset(offset)

                Canvas { context, canvasSize in
                    let bounds = CGRect(origin: .zero, size: canvasSize)
                    for word in result.words {
                        let rect = screenRect(for: word, photo: photo, size: size)
                        guard rect.intersects(bounds) else { continue }
                        draw(word, in: rect, context: &context)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(zoomGesture(in: size).simultaneously(with: panGesture(in: size)))
            .onTapGesture { location in
                let word = word(at: location, photo: photo, size: size)
                withAnimation(.snappy(duration: 0.22)) {
                    // Tapping the selected word again, or empty space, closes the panel.
                    selected = (word == selected) ? nil : word
                }
            }
            .onChange(of: selected) { reveal(selected, photo: photo, size: size) }
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    if voiceOverEnabled {
                        ForEach(result.words) { word in
                            let rect = screenRect(for: word, photo: photo, size: size)
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
    private func word(at point: CGPoint, photo: CGRect, size: CGSize) -> OCRWord? {
        var nearest: (word: OCRWord, distance: CGFloat)?
        for word in result.words {
            let rect = screenRect(for: word, photo: photo, size: size)
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
    private func screenRect(for word: OCRWord, photo: CGRect, size: CGSize) -> CGRect {
        let rect = viewRect(for: word.boundingBox, in: photo)
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
                guard pinchStart == nil else { return }
                offset = clamped(
                    CGSize(width: offset.width + value.translation.width - last.width,
                           height: offset.height + value.translation.height - last.height),
                    in: size
                )
            }
            .onEnded { _ in lastPanTranslation = nil }
    }

    /// Pans just enough to keep the selected word clear of the panel and the
    /// close button. With no selection, settles back within the normal bounds.
    private func reveal(_ word: OCRWord?, photo: CGRect, size: CGSize) {
        var target = offset
        if let word {
            let rect = screenRect(for: word, photo: photo, size: size)
            let visibleTop = topInset
            let visibleBottom = size.height - bottomInset - 20
            if rect.maxY > visibleBottom {
                target.height += visibleBottom - rect.maxY
            } else if rect.minY < visibleTop {
                target.height += visibleTop - rect.minY
            }
        }
        target = clamped(target, in: size)
        guard target != offset else { return }
        withAnimation(.snappy(duration: 0.3)) { offset = target }
    }

    /// Keeps the photo covering the frame (no panning past its edges), plus room
    /// to lift the bottom of the photo above the info panel. The filled photo
    /// overflows the screen on one axis, so it can pan there even at 1×.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let photo = filledRect(in: size)
        let maxX = max(0, (photo.width * scale - size.width) / 2)
        let maxY = max(0, (photo.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY - bottomInset), maxY)
        )
    }

    /// The photo's rect at 1×, scaled to fill `container` and centered, matching
    /// the camera preview's framing.
    private func filledRect(in container: CGSize) -> CGRect {
        let image = result.image.size
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Vision boxes are normalized with a bottom-left origin.
    private func viewRect(for box: CGRect, in photo: CGRect) -> CGRect {
        CGRect(
            x: photo.minX + box.minX * photo.width,
            y: photo.minY + (1 - box.maxY) * photo.height,
            width: box.width * photo.width,
            height: box.height * photo.height
        )
    }
}

// MARK: - Bottom panel

private struct InfoPanel: View {
    let result: OCRResult
    let dictionary: ChineseDictionary
    let translator: SentenceTranslator
    let word: OCRWord?

    var body: some View {
        ScrollView {
            if let word {
                VStack(alignment: .leading, spacing: 32) {
                    WordDetail(word: word.text, entries: dictionary.entries(for: word.text))
                    if let sentence = word.sentence {
                        SentenceTranslation(sentence: result.sentences[sentence.index],
                                            highlight: sentence.range,
                                            translator: translator)
                    }
                }
                .id(word.id)
                .transition(.opacity)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// The tapped word's sentence, with the word highlighted, and its translation.
private struct SentenceTranslation: View {
    let sentence: String
    let highlight: Range<Int>
    let translator: SentenceTranslator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sentence")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            Text(highlighted)
                .font(Theme.Font.hanzi(20))
                .textSelection(.enabled)
            translationLine
        }
    }

    private var highlighted: AttributedString {
        var text = AttributedString(sentence)
        let characters = text.characters
        guard highlight.lowerBound >= 0, highlight.upperBound <= characters.count else { return text }
        let lower = characters.index(characters.startIndex, offsetBy: highlight.lowerBound)
        let upper = characters.index(characters.startIndex, offsetBy: highlight.upperBound)
        text[lower..<upper].foregroundColor = Theme.accent
        return text
    }

    @ViewBuilder
    private var translationLine: some View {
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
