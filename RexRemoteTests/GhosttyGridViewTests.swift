import XCTest
import UIKit
@testable import RexRemote

/// Guards the renderer itself: the grid must put ink on the canvas, not just
/// paint a background, and the cursor must be visible where the core reports it.
final class GhosttyGridViewTests: XCTestCase {
    private func makeView(text: String) throws -> (GhosttyGridView, GhosttySession) {
        let session = try XCTUnwrap(GhosttySession(cols: 24, rows: 6, cellWidthPx: 7, cellHeightPx: 15))
        let view = GhosttyGridView(theme: RexTheme.terminalTheme)
        view.frame = CGRect(x: 0, y: 0, width: 168, height: 90)
        view.applyFont(size: 10)
        view.session = session
        session.write(Array(text.utf8)[...])
        view.layoutIfNeeded()
        return (view, session)
    }

    private func render(_ view: GhosttyGridView) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    func testDrawsInkForText() throws {
        let (view, _) = try makeView(text: "hello\r\nworld")
        let image = render(view)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grid-hello.png"))

        let ink = countDarkPixels(in: image, belowRow: 1)
        XCTAssertGreaterThan(ink, 260, "the renderer drew almost no text (dark pixels: \(ink))")
    }

    /// The block cursor sits in the first row, so blankness is measured from the
    /// second row down: that area must stay paper when nothing was written.
    /// The glyphs must sit inside their row: a baseline computed the wrong way
    /// round clips every ascender, which is invisible to a naive ink count.
    func testGlyphsFillTheWholeRowHeight() throws {
        let (view, _) = try makeView(text: "HHHH")
        let image = render(view)
        let capBand = countDarkPixels(in: image, rows: 0..<1, fraction: 0.15..<0.45)
        let descentBand = countDarkPixels(in: image, rows: 0..<1, fraction: 0.92..<1)
        XCTAssertGreaterThan(capBand, 20, "glyphs are pushed below their row (cap band has \(capBand) dark pixels)")
        XCTAssertLessThan(descentBand, 10, "glyphs spill past their row (\(descentBand) dark pixels)")
    }

    func testEmptyGridIsJustPaper() throws {
        let (view, _) = try makeView(text: "")
        let ink = countDarkPixels(in: render(view), belowRow: 1)
        XCTAssertLessThan(ink, 20, "an empty grid should be blank, got \(ink) dark pixels")
    }

    /// Counts ink inside a vertical slice of the given rows, expressed as a
    /// fraction of the row height so it is independent of the metrics.
    private func countDarkPixels(in image: UIImage, rows: Range<Int>, fraction: Range<Double>) -> Int {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let stride = cgImage.bytesPerRow
        let components = cgImage.bitsPerPixel / 8
        let rowHeight = 15 * image.scale
        let from = Int((CGFloat(rows.lowerBound) * rowHeight + CGFloat(fraction.lowerBound) * rowHeight).rounded())
        let to = Int((CGFloat(rows.lowerBound) * rowHeight + CGFloat(fraction.upperBound) * rowHeight).rounded())
        var count = 0
        for pixelY in max(0, from)..<min(cgImage.height, to) {
            for pixelX in 0..<cgImage.width {
                let offset = pixelY * stride + pixelX * components
                if Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2]) < 380 { count += 1 }
            }
        }
        return count
    }

    private func countDarkPixels(in image: UIImage, belowRow: Int) -> Int {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let stride = cgImage.bytesPerRow
        let components = cgImage.bitsPerPixel / 8
        var count = 0
        // The rendered image is in pixels, the grid in points.
        let firstRow = Int((CGFloat(max(0, belowRow)) * 15 * image.scale).rounded())
        for pixelY in firstRow..<cgImage.height {
            for pixelX in 0..<cgImage.width {
                let offset = pixelY * stride + pixelX * components
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                if red + green + blue < 380 { count += 1 }   // clearly darker than the paper
            }
        }
        return count
    }
}
