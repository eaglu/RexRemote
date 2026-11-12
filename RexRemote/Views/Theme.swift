import GhosttyTerminal
import SwiftUI
import UIKit

/// The app's single light design, matched to Rex on the Mac.
///
/// Warm paper behind warm white cards, hairline borders instead of shadows, dark
/// charcoal chips for the active tab, and a mint glyph as the one loud accent.
/// The terminal keeps Rex's own colours, delivered by the server with the stream.
enum RexTheme {
    /// HIG minimum hit target. Every control that is not a full-width row uses
    /// at least this, even when the glyph inside is smaller.
    static let tapTarget: CGFloat = 44

    /// Light is Rex's own palette; dark keeps the same warm cast instead of
    /// falling back to a neutral grey, so the app still looks like Rex after
    /// sunset.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Window chrome / page background.
    static let paper = dynamic(0xFBF9F1, 0x161412)
    /// Cards, tab strip, panes.
    static let card = dynamic(0xFFFEFA, 0x211E1A)
    /// Capsule that holds the tabs, and other sunken areas.
    static let strip = dynamic(0xF1EDE2, 0x2A2621)
    /// Slightly stronger fill for pressed or secondary chips.
    static let fill = dynamic(0xE8E3D6, 0x35302A)

    static let ink = dynamic(0x2F2A24, 0xF2EEE4)
    static let secondaryInk = dynamic(0x797066, 0xA69C8D)
    static let hairline = dynamic(0xE6E3DA, 0x3C372F)

    /// Dark chip used by the active tab and by primary buttons.
    static let chip = dynamic(0x292B2F, 0x3A3530)
    static let chipInk = dynamic(0xF3F1EA, 0xF4EFE4)
    /// The `>_` glyph — mint on chips, deep green on paper.
    static let mint = dynamic(0x88E987, 0x8FE98D)
    static let mintDeep = dynamic(0x3F8A4B, 0x82DA8F)

    static let warning = dynamic(0xB4541F, 0xFFA071)

    /// One Light, as hex strings so libghostty can use them directly.
    static let terminalPaletteHex: [String] = [
        "#383A42", "#E45649", "#50A14F", "#C18401",
        "#4078F2", "#A626A4", "#0184BC", "#A0A1A7",
        "#696C77", "#DF6C75", "#71B159", "#D0A215",
        "#61AFEF", "#C678DD", "#56B6C2", "#202227"
    ]

    /// The terminal defaults the app paints with until the server sends the Mac's
    /// own theme over the stream.
    static var ghosttyTheme: TerminalTheme {
        TerminalTheme(light: terminalConfiguration(dark: false), dark: terminalConfiguration(dark: true))
    }

    private static func terminalConfiguration(dark: Bool) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(dark ? "#1B1815" : "#FAF8F3")
            builder.withForeground(dark ? "#E7E1D5" : "#38342E")
            builder.withCursorColor(dark ? "#E7E1D5" : "#38342E")
            for (index, colour) in terminalPaletteHex.enumerated() {
                builder.withPalette(index, color: colour)
            }
        }
    }

    /// Fallback terminal colours, used until the server sends the Mac's theme.
    static let terminalBackground = UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0x1B1815 : 0xFAF8F3)
    }
    static let terminalForeground = UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0xE7E1D5 : 0x38342E)
    }
    static let terminalCursor = terminalForeground

    // MARK: - Liquid Glass

    /// Rex's hierarchy translated to iOS 26: only the floating chrome is glass
    /// (top bar, window tabs, input dock). Content — panes, terminal text, the
    /// session list — stays on solid paper, because glass that sits under text
    /// costs legibility for nothing.
    static let chipGlass = Color(uiColor: UIColor(hex: 0x292B2F))

    /// `.regular` glass, optionally tinted and interactive (for tappable chips).
    static func glass(_ tint: Color? = nil, interactive: Bool = false) -> Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Monospaced helpers so header glyphs line up with the terminal grid.
    /// The explicit size is for glyphs whose box is fixed (the `>_` mark); body
    /// text goes through ``monoText`` so Dynamic Type still reaches it.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Dynamic Type scale for every piece of chrome text.
    static func text(_ style: Font.TextStyle = .footnote, weight: Font.Weight = .regular) -> Font {
        .system(style, weight: weight)
    }

    static func monoText(_ style: Font.TextStyle = .caption, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    /// The reader can override the grid size with A−/A+ or a pinch; the
    /// default follows their text setting.
    static let minimumTerminalFontSize: Float = 9
    static let maximumTerminalFontSize: Float = 28
    static let defaultTerminalFontSize: Float = 12
    static let terminalFontSizeKey = "rex.terminal.fontSize"

    /// Terminal point size follows the reader's text setting until they pick
    /// one, clamped so the grid stays usable.
    static var preferredTerminalFontSize: Float {
        let base = CGFloat(defaultTerminalFontSize)
        let scaled = Float(UIFontMetrics(forTextStyle: .body).scaledValue(for: base))
        return min(max(scaled, minimumTerminalFontSize), maximumTerminalFontSize)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Hairline card used by every surface in the app.
struct RexCard: ViewModifier {
    var radius: CGFloat = 10
    var fill: Color = RexTheme.card

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(RexTheme.hairline, lineWidth: 0.8)
            )
    }
}

extension View {
    func rexCard(radius: CGFloat = 10, fill: Color = RexTheme.card) -> some View {
        modifier(RexCard(radius: radius, fill: fill))
    }
}
