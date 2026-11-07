import SwiftUI

/// Centralized, deliberately tiny design system. The product bar is "minimal and
/// slick", so everything here leans on typography, spacing and a single accent.
enum Theme {
    /// Defined once, in the AccentColor asset, which also tints links and buttons.
    static let accent = Color.accentColor

    enum Font {
        /// Large Han character display.
        static func hanzi(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .serif)
        }
        static func pinyin(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .rounded)
        }
    }
}
