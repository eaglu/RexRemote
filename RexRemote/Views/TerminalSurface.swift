import SwiftUI
import UIKit

/// Hosts the libghostty-backed canvas for one block.
struct TerminalSurface: UIViewRepresentable {
    @ObservedObject var controller: TerminalController

    func makeUIView(context: Context) -> GhosttyGridView {
        let view = GhosttyGridView(theme: RexTheme.terminalTheme)
        view.applyFont(size: 10.5)
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: GhosttyGridView, context: Context) {
        uiView.setNeedsDisplay()
    }
}

/// The compact key row: one line of keys the phone keyboard cannot reach.
struct KeyBar: View {
    let controller: TerminalController

    private struct Key: Identifiable {
        let id: String
        let label: String
        let press: GhosttySession.KeyPress?
        let text: String?
    }

    private let keys: [Key] = [
        Key(id: "esc", label: "esc", press: .escape, text: nil),
        Key(id: "tab", label: "tab", press: .tab, text: nil),
        Key(id: "ctrl-c", label: "^C", press: .ctrl("c"), text: nil),
        Key(id: "ctrl-d", label: "^D", press: .ctrl("d"), text: nil),
        Key(id: "ctrl-z", label: "^Z", press: .ctrl("z"), text: nil),
        Key(id: "ctrl-l", label: "^L", press: .ctrl("l"), text: nil),
        Key(id: "up", label: "↑", press: .up, text: nil),
        Key(id: "down", label: "↓", press: .down, text: nil),
        Key(id: "right", label: "→", press: .right, text: nil),
        Key(id: "left", label: "←", press: .left, text: nil),
        Key(id: "pipe", label: "|", press: nil, text: "|"),
        Key(id: "tilde", label: "~", press: nil, text: "~"),
        Key(id: "slash", label: "/", press: nil, text: "/"),
        Key(id: "dash", label: "-", press: nil, text: "-")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys) { key in
                    Button {
                        send(key)
                    } label: {
                        Text(key.label)
                            .font(RexTheme.mono(12, weight: .medium))
                            .frame(minWidth: 34)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
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

    private func send(_ key: Key) {
        // The encoder knows about cursor mode, the Kitty protocol and modifiers;
        // plain text keys are cheaper to send as UTF-8.
        if let press = key.press, let bytes = controller.terminal?.encode(press) {
            controller.type(bytes: bytes)
        } else if let text = key.text {
            controller.type(text)
        }
    }
}
