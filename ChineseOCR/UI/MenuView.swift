import SwiftUI

/// Full-screen app menu. Each option is a row that pushes its own screen.
struct MenuView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                List {
                    NavigationLink {
                        AttributionView()
                            .navigationTitle("Licenses")
                    } label: {
                        Label("Licenses", systemImage: "doc.text")
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.15))
                }
                .listStyle(.plain)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Custom header instead of a toolbar, so the close button has no system background.
    private var header: some View {
        ZStack {
            Text("Menu").font(.headline)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close menu")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }
}
