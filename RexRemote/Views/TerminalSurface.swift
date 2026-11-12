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
    /// A−/A+, pinch and the settings default all write through this key.
    @AppStorage(RexTheme.terminalFontSizeKey) private var storedFontSize =
        Double(RexTheme.preferredTerminalFontSize)

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.controller = GhosttyTerminal.TerminalController.shared
        view.configuration = TerminalSurfaceOptions(
            backend: .inMemory(controller.terminal),
            fontSize: Float(storedFontSize),
            context: .window
        )
        view.delegate = context.coordinator
        // The app has its own key row above the keyboard; Ghostty's accessory
        // row would be a second, redundant one. An empty list makes
        // `inputAccessoryView` nil.
        view.inputAccessoryItems = []
        controller.attach(view)
        context.coordinator.prepare(view: view, fontSize: Float(storedFontSize))
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Re-attach the keyboard after a rebuild, but never take it away from a
        // text field the person is typing into (the compose bar, or libghostty's
        // own hidden input view, which is a text view inside this view).
        if keepKeyboard, !uiView.isFirstResponder, !uiView.hasTextInputFocus {
            uiView.becomeFirstResponder()
        }
        context.coordinator.applyFontSize(Float(storedFontSize), to: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Ghostty reports a clicked hyperlink; iOS decides what opening it means.
    final class Coordinator: NSObject, TerminalSurfaceOpenURLDelegate {
        /// The size the surface is actually drawing at, so a change can be
        /// applied as a delta instead of rebuilding the terminal.
        private var appliedFontSize: Float = 0
        private var lastPinchScale: CGFloat = 1

        func prepare(view: TerminalView, fontSize: Float) {
            appliedFontSize = fontSize.rounded()
            // libghostty ships its own pinch handler; ours writes through
            // `@AppStorage` so the choice survives relaunch, and two
            // recognisers competing on one surface would double the step.
            view.gestureRecognizers?
                .compactMap { $0 as? UIPinchGestureRecognizer }
                .forEach { $0.isEnabled = false }
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            view.addGestureRecognizer(pinch)
        }

        func applyFontSize(_ size: Float, to view: TerminalView) {
            let target = size.rounded()
            let delta = Int(target - appliedFontSize)
            guard delta != 0 else { return }
            let action = delta > 0 ? "increase_font_size:1" : "decrease_font_size:1"
            for _ in 0 ..< abs(delta) {
                _ = view.surface?.performBindingAction(action)
            }
            appliedFontSize = target
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastPinchScale = gesture.scale
            case .changed:
                let steps = Int((gesture.scale - lastPinchScale) / 0.12)
                guard steps != 0 else { return }
                lastPinchScale += CGFloat(steps) * 0.12
                let stored = UserDefaults.standard.double(forKey: RexTheme.terminalFontSizeKey)
                let base = stored > 0 ? Float(stored) : RexTheme.preferredTerminalFontSize
                let next = min(
                    max(base + Float(steps), RexTheme.minimumTerminalFontSize),
                    RexTheme.maximumTerminalFontSize
                )
                UserDefaults.standard.set(Double(next), forKey: RexTheme.terminalFontSizeKey)
            default:
                lastPinchScale = 1
            }
        }

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

        /// VoiceOver would read "↑" as nothing at all.
        var accessibilityLabel: String {
            switch id {
            case "esc": return "Escape"
            case "tab": return "Tab"
            case "ctrl-c": return "Control C"
            case "ctrl-d": return "Control D"
            case "ctrl-z": return "Control Z"
            case "ctrl-a": return "Control A"
            case "ctrl-e": return "Control E"
            case "ctrl-u": return "Control U"
            case "ctrl-w": return "Control W"
            case "ctrl-l": return "Control L"
            case "up": return "Arrow up"
            case "down": return "Arrow down"
            case "left": return "Arrow left"
            case "right": return "Arrow right"
            default: return label
            }
        }
    }

    private let keys: [Key] = [
        Key(id: "esc", label: "esc", press: TerminalKeyPress(.escape)),
        Key(id: "tab", label: "tab", press: TerminalKeyPress(.tab)),
        Key(id: "ctrl-c", label: "^C", press: TerminalKeyPress(.c, modifiers: .ctrl)),
        Key(id: "ctrl-d", label: "^D", press: TerminalKeyPress(.d, modifiers: .ctrl)),
        Key(id: "ctrl-z", label: "^Z", press: TerminalKeyPress(.z, modifiers: .ctrl)),
        Key(id: "ctrl-a", label: "^A", bytes: [0x01]),
        Key(id: "ctrl-e", label: "^E", bytes: [0x05]),
        Key(id: "ctrl-u", label: "^U", bytes: [0x15]),
        Key(id: "ctrl-w", label: "^W", bytes: [0x17]),
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
                            .font(RexTheme.monoText(.callout, weight: .medium))
                            .frame(minWidth: RexTheme.tapTarget, minHeight: RexTheme.tapTarget)
                            .padding(.horizontal, 4)
                            .foregroundStyle(RexTheme.ink)
                            .glassEffect(RexTheme.glass(interactive: true), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key.accessibilityLabel)
                    .accessibilityIdentifier("key-\(key.id)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

private extension UIView {
    /// Whether a text input inside this view (or a sibling) holds the keyboard.
    var hasTextInputFocus: Bool {
        guard let responder = window?.firstResponderInTree() else { return false }
        guard responder is UITextField || responder is UITextView else { return false }
        return (responder as? UIView)?.isDescendant(of: self) != true || responder !== self
    }

    /// UIKit does not expose the current first responder, so walk the tree.
    func firstResponderInTree() -> UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.firstResponderInTree() { return responder }
        }
        return nil
    }
}
