import Foundation
import GhosttyVt

/// One `libghostty-vt` terminal plus the frame we read out of it.
///
/// The library is a C terminal *core*: we hand it the bytes a program writes and
/// it keeps the grid, scrollback, cursor and styles. Everything visual is ours,
/// so this type also snapshots the grid into plain Swift values that the view can
/// draw without touching C from `draw(_:)`.
final class GhosttySession {
    /// Style bits from `style.h`. They are macros, so Swift does not import them.
    enum StyleFlag {
        static let bold: GhosttyStyleFlags = 1 << 0
        static let italic: GhosttyStyleFlags = 1 << 1
        static let faint: GhosttyStyleFlags = 1 << 2
        static let blink: GhosttyStyleFlags = 1 << 3
        static let inverse: GhosttyStyleFlags = 1 << 4
        static let invisible: GhosttyStyleFlags = 1 << 5
        static let strikethrough: GhosttyStyleFlags = 1 << 6
        static let overline: GhosttyStyleFlags = 1 << 7
    }

    struct RGB: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8

        static let black = RGB(red: 0, green: 0, blue: 0)

        init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ rgb: GhosttyColorRgb) {
            self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
        }

        /// `#RRGGBB` as the server sends it in the theme directive.
        init?(hex: String?) {
            guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
            if text.hasPrefix("#") { text.removeFirst() }
            guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
            self.init(
                red: UInt8((value >> 16) & 0xFF),
                green: UInt8((value >> 8) & 0xFF),
                blue: UInt8(value & 0xFF)
            )
        }
    }

    struct Cell {
        var text: String = ""
        /// nil means "no colour of its own": draw with the theme's default.
        var foreground: RGB?
        var background: RGB?
        var bold = false
        var italic = false
        var faint = false
        var underline = false
        var strikethrough = false
        var inverse = false
    }

    struct Frame {
        var rows: [[Cell]] = []
        var cols = 0
        var cursor: (x: Int, y: Int)?
        var cursorVisible = false
        var cursorBlinking = false
        var cursorStyle: GhosttyCursorStyle = GHOSTTY_CURSOR_STYLE_BLOCK
    }

    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var frame = Frame()

    private(set) var terminal: GhosttyTerminal?
    private var renderState: GhosttyRenderState?
    private var rowIterator: GhosttyRenderStateRowIterator?
    private var rowCells: GhosttyRenderStateRowCells?
    private var graphemeBuffer = [UInt8](repeating: 0, count: 256)

    var isReady: Bool { terminal != nil }

    init?(cols: Int, rows: Int, cellWidthPx: UInt32, cellHeightPx: UInt32) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)

        var terminal: GhosttyTerminal?
        guard ghostty_terminal_new(nil, &terminal, UInt16(self.cols), UInt16(self.rows)) == GHOSTTY_SUCCESS,
              let terminal else { return nil }
        self.terminal = terminal
        _ = ghostty_terminal_resize(terminal, UInt16(cols), UInt16(rows), cellWidthPx, cellHeightPx)

        var state: GhosttyRenderState?
        guard ghostty_render_state_new(nil, &state) == GHOSTTY_SUCCESS, let state else { return nil }
        renderState = state

        var iterator: GhosttyRenderStateRowIterator?
        guard ghostty_render_state_row_iterator_new(nil, &iterator) == GHOSTTY_SUCCESS, let iterator else {
            return nil
        }
        rowIterator = iterator

        var cells: GhosttyRenderStateRowCells?
        guard ghostty_render_state_row_cells_new(nil, &cells) == GHOSTTY_SUCCESS, let cells else { return nil }
        rowCells = cells

        rebuildFrame()
    }

    deinit {
        if let rowCells { ghostty_render_state_row_cells_free(rowCells) }
        if let rowIterator { ghostty_render_state_row_iterator_free(rowIterator) }
        if let renderState { ghostty_render_state_free(renderState) }
        if let terminal { ghostty_terminal_free(terminal) }
    }

    // MARK: - Feeding bytes

    /// Hand a chunk of the byte stream to the terminal and refresh the frame.
    func write(_ bytes: ArraySlice<UInt8>) {
        guard let terminal, !bytes.isEmpty else { return }
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = ghostty_terminal_vt_write(terminal, base, buffer.count)
        }
        rebuildFrame()
    }

    func resize(cols newCols: Int, rows newRows: Int, cellWidthPx: UInt32, cellHeightPx: UInt32) {
        let clampedCols = max(1, newCols)
        let clampedRows = max(1, newRows)
        guard clampedCols != cols || clampedRows != rows else { return }
        cols = clampedCols
        rows = clampedRows
        guard let terminal else { return }
        ghostty_terminal_resize(terminal, UInt16(clampedCols), UInt16(clampedRows), cellWidthPx, cellHeightPx)
        rebuildFrame()
    }

    // MARK: - Theme

    func setColors(foreground: RGB, background: RGB, cursor: RGB?, palette: [RGB]) {
        guard let terminal else { return }
        var fg = GhosttyColorRgb(r: foreground.red, g: foreground.green, b: foreground.blue)
        var bg = GhosttyColorRgb(r: background.red, g: background.green, b: background.blue)
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &fg)
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &bg)
        if let cursor {
            var color = GhosttyColorRgb(r: cursor.red, g: cursor.green, b: cursor.blue)
            _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &color)
        }
        guard palette.count == 16 else { return }
        let colors = Self.palette256(seeds: palette).map { GhosttyColorRgb(r: $0.red, g: $0.green, b: $0.blue) }
        colors.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, base)
        }
        // Existing cells carry resolved colours, so redraw the frame from the new
        // palette instead of waiting for the next byte.
        rebuildFrame()
    }

    /// The theme carries the 16 base colours; the library wants all 256, so the
    /// colour cube and grey ramp are filled in the standard way.
    static func palette256(seeds: [RGB]) -> [RGB] {
        var palette = [RGB](repeating: .black, count: 256)
        for (index, color) in seeds.prefix(16).enumerated() { palette[index] = color }
        let steps: [UInt8] = [0, 95, 135, 175, 215, 255]
        for index in 16..<232 {
            let value = index - 16
            palette[index] = RGB(red: steps[value / 36], green: steps[(value / 6) % 6], blue: steps[value % 6])
        }
        for index in 232..<256 {
            let level = UInt8(8 + (index - 232) * 10)
            palette[index] = RGB(red: level, green: level, blue: level)
        }
        return palette
    }

    // MARK: - Reading the grid

    private func rebuildFrame() {
        guard let terminal, let renderState, let recycled = rowIterator, var rowCells else { return }
        guard ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS else { return }

        // The iterator is only usable after the render state hands it out; a
        // freshly created one walks nothing.
        guard let rowIterator = Self.bind(iterator: recycled, of: renderState) else { return }
        self.rowIterator = rowIterator

        var frame = Frame()
        frame.cols = cols
        frame.rows.reserveCapacity(rows)

        while ghostty_render_state_row_iterator_next(rowIterator) {
            var cells: [Cell] = []
            cells.reserveCapacity(cols)
            let fetched = withUnsafeMutablePointer(to: &rowCells) { pointer -> GhosttyResult in
                ghostty_render_state_row_get(
                    rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, UnsafeMutableRawPointer(pointer)
                )
            }
            if fetched == GHOSTTY_SUCCESS {
                while ghostty_render_state_row_cells_next(rowCells) {
                    cells.append(self.cell(from: rowCells))
                }
            }
            frame.rows.append(cells)
        }
        self.rowCells = rowCells

        var visible = false
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &visible)
        frame.cursorVisible = visible
        if visible {
            var hasValue = false
            var cursorX: UInt16 = 0
            var cursorY: UInt16 = 0
            _ = ghostty_render_state_get(
                renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &hasValue
            )
            if hasValue,
               ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cursorX) == GHOSTTY_SUCCESS,
               ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cursorY) == GHOSTTY_SUCCESS {
                frame.cursor = (Int(cursorX), Int(cursorY))
            }
        }
        var blinking = false
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING, &blinking)
        frame.cursorBlinking = blinking
        var style = GHOSTTY_CURSOR_STYLE_BLOCK
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &style)
        frame.cursorStyle = style

        self.frame = frame
        _ = ghostty_render_state_clean(renderState)
    }

    private func cell(from cells: GhosttyRenderStateRowCells) -> Cell {
        var cell = Cell()

        var style = GhosttyStyle()
        let styleResult = withUnsafeMutablePointer(to: &style) { pointer in
            ghostty_render_state_row_cells_get(
                cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, UnsafeMutableRawPointer(pointer)
            )
        }
        if styleResult == GHOSTTY_SUCCESS {
            cell.bold = style.flags & StyleFlag.bold != 0
            cell.italic = style.flags & StyleFlag.italic != 0
            cell.faint = style.flags & StyleFlag.faint != 0
            cell.underline = style.flags & StyleFlag.inverse == 0 && styleHexUnderline(style.flags)
            cell.strikethrough = style.flags & StyleFlag.strikethrough != 0
            cell.inverse = style.flags & StyleFlag.inverse != 0
        }

        graphemeBuffer.withUnsafeMutableBufferPointer { buffer in
            var utf8 = GhosttyBuffer(ptr: buffer.baseAddress, cap: buffer.count, len: 0)
            let result = withUnsafeMutablePointer(to: &utf8) { pointer in
                ghostty_render_state_row_cells_get(
                    cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_UTF8, UnsafeMutableRawPointer(pointer)
                )
            }
            if result == GHOSTTY_SUCCESS, utf8.len > 0, let base = utf8.ptr {
                cell.text = String(decoding: UnsafeBufferPointer(start: base, count: utf8.len), as: UTF8.self)
            }
        }

        var background = GhosttyColorRgb(r: 0, g: 0, b: 0)
        let bgResult = withUnsafeMutablePointer(to: &background) { pointer in
            ghostty_render_state_row_cells_get(
                cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, UnsafeMutableRawPointer(pointer)
            )
        }
        if bgResult == GHOSTTY_SUCCESS { cell.background = RGB(background) }

        var foreground = GhosttyColorRgb(r: 0, g: 0, b: 0)
        let fgResult = withUnsafeMutablePointer(to: &foreground) { pointer in
            ghostty_render_state_row_cells_get(
                cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, UnsafeMutableRawPointer(pointer)
            )
        }
        if fgResult == GHOSTTY_SUCCESS { cell.foreground = RGB(foreground) }

        return cell
    }

    /// Asks the render state for the iterator it will actually walk.
    private static func bind(
        iterator: GhosttyRenderStateRowIterator?,
        of renderState: GhosttyRenderState
    ) -> GhosttyRenderStateRowIterator? {
        var bound = iterator
        let result = withUnsafeMutablePointer(to: &bound) { pointer in
            ghostty_render_state_get(
                renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, UnsafeMutableRawPointer(pointer)
            )
        }
        return result == GHOSTTY_SUCCESS ? bound : nil
    }

    /// Underline lives in bits 8..10 of the flags: zero means none.
    private func styleHexUnderline(_ flags: GhosttyStyleFlags) -> Bool {
        (flags >> 8) & 0x7 != 0
    }

    /// The screen as plain text, for tests and logs.
    func plainText() -> String {
        guard let terminal else { return "" }
        var formatter: GhosttyFormatter?
        guard ghostty_formatter_terminal_new(nil, &formatter, terminal) == GHOSTTY_SUCCESS, let formatter else {
            return ""
        }
        defer { ghostty_formatter_free(formatter) }

        var emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
        _ = ghostty_formatter_set(formatter, GHOSTTY_FORMATTER_OPT_EMIT, &emit)
        var trim = true
        _ = ghostty_formatter_set(formatter, GHOSTTY_FORMATTER_OPT_TRIM, &trim)

        var buffer: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard ghostty_formatter_format_alloc(formatter, nil, &buffer, &length) == GHOSTTY_SUCCESS,
              let buffer else { return "" }
        defer { ghostty_free(nil, buffer, length) }
        return String(decoding: UnsafeBufferPointer(start: buffer, count: length), as: UTF8.self)
    }
}
