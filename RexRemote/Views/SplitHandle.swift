import SwiftUI

/// The draggable border between two panes.
///
/// The layout tree reports where the border sits and how the space is split, so
/// a drag only has to turn pixels into a fraction and ask the server to move it.
/// The line commits on release: `session.resize_pane` is an ordered method, and
/// firing it per frame would queue dozens of calls behind the same border.
struct SplitHandle: View {
    let divider: SplitDivider
    let size: CGSize
    let isActive: Bool
    let onCommit: (Double) -> Void

    @State private var dragRatio: Double?
    @State private var isDragging = false

    private var area: CGRect {
        CGRect(
            x: divider.rect.minX * size.width,
            y: divider.rect.minY * size.height,
            width: divider.rect.width * size.width,
            height: divider.rect.height * size.height
        )
    }

    private var ratio: Double { dragRatio ?? divider.ratio }

    private var isHorizontal: Bool { divider.direction == "horizontal" }

    var body: some View {
        let area = area
        let line = isHorizontal
            ? CGSize(width: 2, height: max(area.height - 10, 8))
            : CGSize(width: max(area.width - 10, 8), height: 2)
        let center = isHorizontal
            ? CGPoint(x: area.minX + area.width * ratio, y: area.midY)
            : CGPoint(x: area.midX, y: area.minY + area.height * ratio)

        ZStack {
            Capsule()
                .fill(isDragging || isActive ? RexTheme.mintDeep.opacity(0.85) : RexTheme.hairline)
                .frame(width: line.width, height: line.height)
        }
        .frame(
            width: isHorizontal ? 26 : area.width,
            height: isHorizontal ? area.height : 26
        )
        .contentShape(Rectangle())
        .position(x: isHorizontal ? center.x : area.midX,
                  y: isHorizontal ? area.midY : center.y)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    isDragging = true
                    let span = isHorizontal ? area.width : area.height
                    let travel = isHorizontal ? value.translation.width : value.translation.height
                    guard span > 0 else { return }
                    let moved = divider.ratio + Double(travel / span)
                    dragRatio = min(max(moved, 0.08), 0.92)
                }
                .onEnded { _ in
                    isDragging = false
                    if let dragRatio { onCommit(dragRatio) }
                    dragRatio = nil
                }
        )
        .accessibilityIdentifier("splitHandle")
    }
}
