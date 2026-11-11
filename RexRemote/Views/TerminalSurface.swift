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
        view.delegate = context.coordinator
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        if keepKeyboard, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Ghostty reports a clicked hyperlink; iOS decides what opening it means.
    final class Coordinator: NSObject, TerminalSurfaceOpenURLDelegate {
        func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
            guard let target = URL(string: url) else { return }
            let allowed: Set<String> = ["http", "https", "mailto", "ssh", "ftp"]
            guard let scheme = target.scheme?.lowercased(), allowed.contains(scheme) else { return }
            UIApplication.shared.open(target)
        }
    }
}

/// The compact key row: one line of keys the phone keyboard cannot reach.
struct KeyBar: View {
    let controller: TerminalController

    private struct Key: Identifiable {
        let id: String
        let label: String
        /// A press handed to libghostty's encoder, which is the only way to get
        /// arrows right: applications move the cursor keys into SS3 or into
        /// ``CSI 1;<mods>`` depending on the mode they set.
        var press: TerminalKeyPress?
        /// Literal bytes for keys that type text rather than name a key.
        var bytes: [UInt8] = []
    }

    private let keys: [Key] = [
        Key(id: "esc", label: "esc", press: TerminalKeyPress(.escape)),
        Key(id: "tab", label: "tab", press: TerminalKeyPress(.tab)),
        Key(id: "ctrl-c", label: "^C", press: TerminalKeyPress(.c, modifiers: .ctrl)),
        Key(id: "ctrl-d", label: "^D", press: TerminalKeyPress(.d, modifiers: .ctrl)),
        Key(id: "ctrl-z", label: "^Z", press: TerminalKeyPress(.z, modifiers: .ctrl)),
        Key(id: "ctrl-l", label: "^L", press: TerminalKeyPress(.l, modifiers: .ctrl)),
        Key(id: "up", label: "↑", press: TerminalKeyPress(.arrowUp)),
        Key(id: "down", label: "↓", press: TerminalKeyPress(.arrowDown)),
        Key(id: "right", label: "→", press: TerminalKeyPress(.arrowRight)),
        Key(id: "left", label: "←", press: TerminalKeyPress(.arrowLeft)),
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
                        if let press = key.press {
                            controller.sendKey(press)
                        } else {
                            controller.type(bytes: key.bytes)
                        }
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
