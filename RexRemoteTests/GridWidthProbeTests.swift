import XCTest
@testable import RexRemote

final class GridWidthProbeTests: XCTestCase {
    private func inkColumns(_ image: UIImage) -> (Int, Int) {
        guard let cg = image.cgImage else { return (0, 0) }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var first = width
        var last = 0
        for x in 0..<width {
            for y in 0..<height {
                let offset = (y * width + x) * 4
                if Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) < 480 {
                    first = min(first, x)
                    last = max(last, x)
                }
            }
        }
        return (first, last)
    }

    func testLastColumnIsDrawn() {
        let session = GhosttySession(cols: 27, rows: 2, cellWidthPx: 21, cellHeightPx: 39)
        XCTAssertNotNil(session)
        session?.write(Array((String(repeating: "A", count: 26) + "X").utf8)[...])
        guard let session else { return }
        let view = GhosttyGridView(theme: ghosttyTheme())
        view.session = session
        view.frame = CGRect(x: 0, y: 0, width: 27 * 7, height: 2 * 13)
        view.applyFont(size: 11)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { context in view.layer.render(in: context.cgContext) }
        let (first, last) = inkColumns(image)
        print("INK first=\(first) last=\(last) width=\(image.size.width) rows=\(session.frame.rows.count) cols=\(session.frame.cols)")
        XCTAssertLessThan(first, 4, "the first column must not be clipped")
        XCTAssertGreaterThan(last, Int(27 * 7) - 12, "the last column must have ink")
    }

    private func ghosttyTheme() -> GhosttyGridView.Theme {
        GhosttyGridView.Theme(
            background: .white,
            foreground: .black,
            cursor: .black,
            palette: Array(repeating: .black, count: 256)
        )
    }
}
