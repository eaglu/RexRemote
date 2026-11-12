import SwiftUI

/// The capsule that holds the window tabs, with the active window as a dark
/// chip and a `+` for a new one. Long-press a tab to rename or close it.
struct WindowTabStrip: View {
    let windows: [WindowInfo]
    let activeWindowID: String?
    let namespace: Namespace.ID
    let onSelect: (WindowInfo) -> Void
    let onNew: () -> Void
    let onRename: (WindowInfo) -> Void
    let onClose: (WindowInfo) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(windows) { candidate in
                            tab(candidate, isActive: candidate.id == activeWindowID)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                Button(action: onNew) {
                    Image(systemName: "plus")
                        .font(RexTheme.text(.headline, weight: .semibold))
                        .foregroundStyle(RexTheme.ink)
                        .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                        .glassEffect(RexTheme.glass(interactive: true), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New window")
                .accessibilityIdentifier("newWindowChip")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func tab(_ candidate: WindowInfo, isActive: Bool) -> some View {
        Button {
            onSelect(candidate)
        } label: {
            HStack(spacing: 6) {
                Text(">_")
                    .font(RexTheme.mono(13, weight: .bold))
                    .foregroundStyle(isActive ? RexTheme.mint : RexTheme.secondaryInk.opacity(0.7))
                    .accessibilityHidden(true)
                Text(candidate.label)
                    .font(RexTheme.text(.subheadline, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? RexTheme.chipInk : RexTheme.secondaryInk)
                    .lineLimit(1)
                Text("\(candidate.panes.count)")
                    .font(RexTheme.monoText(.caption2))
                    .foregroundStyle(isActive ? RexTheme.chipInk.opacity(0.6) : RexTheme.secondaryInk.opacity(0.7))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .glassEffect(
                isActive
                    ? RexTheme.glass(RexTheme.chipGlass.opacity(0.92), interactive: true)
                    : RexTheme.glass(interactive: true),
                in: .capsule
            )
            .glassEffectID(candidate.id, in: namespace)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.label) window, \(candidate.panes.count) panes")
        .accessibilityIdentifier("windowTab-\(candidate.label)")
        .contextMenu {
            Button("Rename window…") { onRename(candidate) }
            Button("Close window", role: .destructive) { onClose(candidate) }
        }
    }
}
