import GhosttyTerminal
import SwiftUI
import UIKit

/// The app's single light design, matched to Rex on the Mac.
///
/// Warm paper behind warm white cards, hairline borders instead of shadows, dark
/// charcoal chips for the active tab, and a mint glyph as the one loud accent.
/// The terminal keeps Rex's own colours, delivered by the server with the stream.
enum RexTheme {
    /// Window chrome / page background.
    static let paper = Color(uiColor: UIColor(hex: 0xFBF9F1))
    /// Cards, tab strip, panes.
    static let card = Color(uiColor: UIColor(hex: 0xFFFEFA))
    /// Capsule that holds the tabs, and other sunken areas.
    static let strip = Color(uiColor: UIColor(hex: 0xF1EDE2))
    /// Slightly stronger fill for pressed or secondary chips.
    static let fill = Color(uiColor: UIColor(hex: 0xE8E3D6))

    static let ink = Color(uiColor: UIColor(hex: 0x2F2A24))
    static let secondaryInk = Color(uiColor: UIColor(hex: 0x797066))
    static let hairline = Color(uiColor: UIColor(hex: 0xE6E3DA))

    /// Dark chip used by the active tab and by primary buttons.
    static let chip = Color(uiColor: UIColor(hex: 0x292B2F))
    static let chipInk = Color(uiColor: UIColor(hex: 0xF3F1EA))
    /// The `>_` glyph — mint on chips, deep green on paper.
    static let mint = Color(uiColor: UIColor(hex: 0x88E987))
    static let mintDeep = Color(uiColor: UIColor(hex: 0x3F8A4B))

    static let warning = Color(uiColor: UIColor(hex: 0xB4541F))

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
        let configuration = TerminalConfiguration { builder in
            builder.withBackground("#FAF8F3")
            builder.withForeground("#38342E")
            builder.withCursorColor("#38342E")
            for (index, colour) in terminalPaletteHex.enumerated() {
                builder.withPalette(index, color: colour)
            }
        }
        return TerminalTheme(light: configuration, dark: configuration)
    }

    /// Fallback terminal colours, used until the server sends the Mac's theme.
    static let terminalBackground = UIColor(hex: 0xFAF8F3)
    static let terminalForeground = UIColor(hex: 0x38342E)
    static let terminalCursor = UIColor(hex: 0x38342E)

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
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
