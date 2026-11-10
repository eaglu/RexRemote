import GhosttyTerminal
import SwiftUI
import UIKit

/// Hosts libghostty's own terminal view for one block. libghostty renders with
/// Metal, so selection, links, wide characters and the cursor all behave like the
/// Mac app instead of being reimplemented here.
struct TerminalSurface: UIViewRepresentable {
    @ObservedObject var controller: TerminalController
    /// Keep the keyboard attached while the pane is the focused one, even when a
    /// server event rebuilds the view hierarchy.
    var keepKeyboard: Bool = true

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.controller = GhosttyTerminal.TerminalController.shared
        view.configuration = TerminalSurfaceOptions(
            backend: .inMemory(controller.terminal),
            fontSize: 11,
            context: .window
        )
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        if keepKeyboard, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
}

/// The compact key row: one line of keys the phone keyboard cannot reach.
struct KeyBar: View {
    let controller: TerminalController

    private struct Key: Identifiable {
        let id: String
        let label: String
        let bytes: [UInt8]
    }

    private static let escape: UInt8 = 0x1B

    private let keys: [Key] = [
        Key(id: "esc", label: "esc", bytes: [0x1B]),
        Key(id: "tab", label: "tab", bytes: [0x09]),
        Key(id: "ctrl-c", label: "^C", bytes: [0x03]),
        Key(id: "ctrl-d", label: "^D", bytes: [0x04]),
        Key(id: "ctrl-z", label: "^Z", bytes: [0x1A]),
        Key(id: "ctrl-l", label: "^L", bytes: [0x0C]),
        Key(id: "up", label: "↑", bytes: [escape, 0x5B, 0x41]),
        Key(id: "down", label: "↓", bytes: [escape, 0x5B, 0x42]),
        Key(id: "right", label: "→", bytes: [escape, 0x5B, 0x43]),
        Key(id: "left", label: "←", bytes: [escape, 0x5B, 0x44]),
        Key(id: "pipe", label: "|", bytes: Array("|".utf8)),
        Key(id: "tilde", label: "~", bytes: Array("~".utf8)),
        Key(id: "slash", label: "/", bytes: Array("/".utf8)),
        Key(id: "dash", label: "-", bytes: Array("-".utf8))
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys) { key in
                    Button {
                        controller.type(bytes: key.bytes)
                    } label: {
                        Text(key.label)
                            .font(RexTheme.mono(13.5, weight: .medium))
                            .frame(minWidth: 40, minHeight: 38)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(RexTheme.ink)
                            .glassEffect(RexTheme.glass(interactive: true), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("key-\(key.id)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}
