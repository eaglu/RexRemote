import CoreText
import UIKit

/// The terminal canvas: draws a `GhosttySession` frame with Core Text and turns
/// touches, the software keyboard and hardware keys into terminal input.
final class GhosttyGridView: UIView {
    struct Theme {
        var background: UIColor
        var foreground: UIColor
        var cursor: UIColor
        var palette: [UIColor]
    }

    /// Called when the pane is tapped, so the store can move the server's focus.
    var onTap: (() -> Void)?
    /// Bytes produced by hardware keyboards and the on-screen keyboard.
    var onInput: (([UInt8]) -> Void)?
    /// Reports the grid the view managed to fit, so the pty can be resized.
    var onGridChange: ((Int, Int, CGSize) -> Void)?

    var theme: Theme {
        didSet { setNeedsDisplay() }
    }

    var session: GhosttySession? {
        didSet { refreshMetrics(); setNeedsDisplay() }
    }

    private var font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var boldFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    private var italicFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var cellSize = CGSize(width: 7, height: 14)
    /// Distance from the top of a cell to its text baseline. Derived from the font
    /// so caps and ascenders stay inside the cell instead of being clipped.
    private var baselineOffset: CGFloat = 10
    private var lines: [String: CTLine] = [:]
    private var blinkOn = true
    private var blinkTimer: Timer?
    /// Invisible text view that owns the system keyboard. Using a real text view
    /// is what lets an IME (pinyin, kana, …) compose before anything is sent: the
    /// grid itself would otherwise receive every pre-edit letter as a keystroke.
    private let inputField = TerminalInputField()

    // MARK: - Init

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = theme.background
        isMultipleTouchEnabled = false
        contentMode = .redraw
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        inputField.onCommit = { [weak self] text in
            self?.onInput?(Array(text.utf8))
        }
        inputField.onDelete = { [weak self] in
            self?.onInput?([0x7F])
        }
        inputField.onKey = { [weak self] bytes in
            self?.onInput?(bytes)
        }
        addSubview(inputField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { blinkTimer?.invalidate() }

    // MARK: - Metrics

    func applyFont(size: CGFloat) {
        font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        boldFont = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        italicFont = font.withTraits(.traitItalic) ?? font
        lines.removeAll()
        refreshMetrics()
        setNeedsDisplay()
    }

    private func refreshMetrics() {
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        // Whole-point cells keep glyphs on the pixel grid; the fraction is picked
        // up by the trailing padding rather than by stretching every cell.
        cellSize = CGSize(width: ceil(advance), height: ceil(font.lineHeight))
        baselineOffset = (cellSize.height - font.lineHeight) / 2 + font.ascender
        guard cellSize.width > 0, cellSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let cols = max(1, Int(bounds.width / cellSize.width))
        let rows = max(1, Int(bounds.height / cellSize.height))
        session?.resize(
            cols: cols,
            rows: rows,
            cellWidthPx: UInt32(cellSize.width * contentScaleFactor),
            cellHeightPx: UInt32(cellSize.height * contentScaleFactor)
        )
        onGridChange?(cols, rows, CGSize(
            width: cellSize.width * contentScaleFactor,
            height: cellSize.height * contentScaleFactor
        ))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshMetrics()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(theme.background.cgColor)
        context.fill(bounds)
        guard let frame = session?.frame, !frame.rows.isEmpty else { return }

        // UIKit hands us a y-down context while Core Text draws y-up; without this
        // flip every glyph is mirrored below its baseline and clipped away.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let colsPerRow = frame.cols
        for (rowIndex, row) in frame.rows.enumerated() {
            let y = CGFloat(rowIndex) * cellSize.height
            if y > bounds.height { break }
            drawRow(row, rowIndex: rowIndex, cols: colsPerRow, context: context)
        }
        drawCursor(in: frame, context: context)
    }

    private func drawRow(_ row: [GhosttySession.Cell], rowIndex: Int, cols: Int, context: CGContext) {
        let y = CGFloat(rowIndex) * cellSize.height

        // Backgrounds first: consecutive cells that share a colour become one fill.
        var runStart = 0
        var runColor: UIColor?
        for index in 0...row.count {
            let color = index < row.count ? background(for: row[index]) : nil
            if color != runColor || index == row.count {
                if let runColor, index > runStart {
                    let rect = CGRect(
                        x: CGFloat(runStart) * cellSize.width,
                        y: y,
                        width: CGFloat(index - runStart) * cellSize.width,
                        height: cellSize.height
                    )
                    context.setFillColor(runColor.cgColor)
                    context.fill(rect)
                }
                runStart = index
                runColor = color
            }
        }

        // Then the glyphs.
        for (column, cell) in row.enumerated() where !cell.text.isEmpty {
            let attributes = attributes(for: cell)
            let line = cachedLine(cell.text, attributes: attributes)
            let x = CGFloat(column) * cellSize.width
            context.saveGState()
            context.clip(to: CGRect(
                x: x,
                y: y,
                width: cellSize.width * max(1, CGFloat(cell.text.cellWidth)),
                height: cellSize.height
            ))
            // CTLineDraw paints with the context's fill colour, not with the
            // attributed string's, so the glyph colour has to be set here.
            context.setFillColor(foreground(for: cell).cgColor)
            context.textPosition = CGPoint(x: x, y: y + baselineOffset)
            CTLineDraw(line, context)
            context.restoreGState()
            drawDecorations(for: cell, column: column, y: y, context: context)
        }
    }

    private func drawDecorations(
        for cell: GhosttySession.Cell,
        column: Int,
        y: CGFloat,
        context: CGContext
    ) {
        guard cell.underline || cell.strikethrough else { return }
        context.setStrokeColor(foreground(for: cell).cgColor)
        context.setLineWidth(1)
        let x = CGFloat(column) * cellSize.width
        if cell.underline {
            context.move(to: CGPoint(x: x, y: y + cellSize.height - 1.5))
            context.addLine(to: CGPoint(x: x + cellSize.width, y: y + cellSize.height - 1.5))
        }
        if cell.strikethrough {
            let middle = y + cellSize.height / 2
            context.move(to: CGPoint(x: x, y: middle))
            context.addLine(to: CGPoint(x: x + cellSize.width, y: middle))
        }
        context.strokePath()
    }

    private func drawCursor(in frame: GhosttySession.Frame, context: CGContext) {
        guard frame.cursorVisible, let cursor = frame.cursor, blinkOn else { return }
        let rect = CGRect(
            x: CGFloat(cursor.x) * cellSize.width,
            y: CGFloat(cursor.y) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
        context.setFillColor(theme.cursor.cgColor)
        switch frame.cursorStyle.rawValue {
        case 0:
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height))
        case 2:
            context.fill(CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2))
        case 3:
            context.setStrokeColor(theme.cursor.cgColor)
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        default:
            // A filled block also needs its glyph redrawn in the background colour.
            context.fill(rect)
            if cursor.y < frame.rows.count, cursor.x < frame.rows[cursor.y].count {
                let cell = frame.rows[cursor.y][cursor.x]
                if !cell.text.isEmpty {
                    var inverted = cell
                    inverted.background = cell.foreground
                    inverted.foreground = cell.background
                    let line = cachedLine(cell.text, attributes: attributes(for: inverted))
                    context.textPosition = CGPoint(x: rect.minX, y: rect.minY + baselineOffset)
                    CTLineDraw(line, context)
                }
            }
        }
    }

    // MARK: - Colours

    private func background(for cell: GhosttySession.Cell) -> UIColor? {
        if cell.inverse {
            return color(for: cell.foreground) ?? theme.foreground
        }
        guard let background = cell.background else { return nil }
        return UIColor(red: CGFloat(background.red) / 255, green: CGFloat(background.green) / 255,
                       blue: CGFloat(background.blue) / 255, alpha: 1)
    }

    private func foreground(for cell: GhosttySession.Cell) -> UIColor {
        if cell.inverse {
            return color(for: cell.background) ?? theme.background
        }
        return color(for: cell.foreground) ?? theme.foreground
    }

    private func color(for rgb: GhosttySession.RGB?) -> UIColor? {
        guard let rgb else { return nil }
        return UIColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                      blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    private func attributes(for cell: GhosttySession.Cell) -> [NSAttributedString.Key: Any] {
        var chosenFont = cell.bold ? boldFont : font
        if cell.italic, let italic = cell.italicFontFallback(bold: cell.bold) {
            chosenFont = italic
        }
        var color = foreground(for: cell)
        if cell.faint { color = color.withAlphaComponent(0.6) }
        return [
            .font: chosenFont,
            .foregroundColor: color
        ]
    }

    private func cachedLine(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CTLine {
        let fontKey = (attributes[.font] as? UIFont)?.fontName ?? "font"
        let color = (attributes[.foregroundColor] as? UIColor).map { colorKey($0) } ?? "color"
        let key = "\(text)|\(fontKey)|\(color)"
        if let cached = lines[key] { return cached }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if lines.count > 1024 { lines.removeAll(keepingCapacity: true) }
        lines[key] = line
        return line
    }

    private func colorKey(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%.3f-%.3f-%.3f-%.3f", red, green, blue, alpha)
    }

    // MARK: - Touch

    @objc private func handleTap() {
        onTap?()
        inputField.becomeFirstResponder()
    }

    // MARK: - Keyboard

    func dismissKeyboard() {
        inputField.resignFirstResponder()
    }
}

/// Keyboard host for `GhosttyGridView`.
///
/// Composition text (marked text) stays inside this view, so a pinyin session
/// only reaches the pty once the user picks a character; plain typing is
/// forwarded one commit at a time.
final class TerminalInputField: UITextView, UITextViewDelegate {
    var onCommit: ((String) -> Void)?
    var onDelete: (() -> Void)?
    /// Raw bytes for keys the grid handles itself (escape, tab, arrows).
    var onKey: (([UInt8]) -> Void)?

    private var forwarding = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
        delegate = self
        alpha = 0.02
        backgroundColor = .clear
        tintColor = .clear
        textColor = .clear
        isScrollEnabled = false
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        keyboardAppearance = .light
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeFirstResponder: Bool { true }

    func textViewDidChange(_ textView: UITextView) {
        guard !forwarding, markedTextRange == nil else { return }
        let pending = text ?? ""
        guard !pending.isEmpty else { return }
        forwarding = true
        text = ""
        forwarding = false
        onCommit?(pending)
    }

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onDelete?()
        } else {
            super.deleteBackward()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardEscape: onKey?([0x1B])
            case .keyboardTab: onKey?([0x09])
            case .keyboardUpArrow: onKey?(Array("\u{1B}[A".utf8))
            case .keyboardDownArrow: onKey?(Array("\u{1B}[B".utf8))
            case .keyboardRightArrow: onKey?(Array("\u{1B}[C".utf8))
            case .keyboardLeftArrow: onKey?(Array("\u{1B}[D".utf8))
            default: super.pressesBegan([press], with: event)
            }
        }
    }
}

private extension String {
    /// Rough display width, so a wide grapheme can spill into its neighbour's cell.
    var cellWidth: Int {
        var width = 0
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
                 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F,
                 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
                width += 2
            default:
                width += 1
            }
        }
        return max(1, width)
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return nil
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension GhosttySession.Cell {
    func italicFontFallback(bold: Bool) -> UIFont? {
        let base = UIFont.monospacedSystemFont(ofSize: 11, weight: bold ? .bold : .regular)
        return base.withTraits(.traitItalic)
    }
}
