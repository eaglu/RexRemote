import SwiftUI

/// The two input bars: the key row, then the compose field with its send
/// button. Fixed to the bottom of the screen so the keyboard and the panes never
/// fight over the same space.
struct InputDock: View {
    let controller: TerminalController
    let prompt: String?
    let canSend: Bool
    @Binding var composeText: String
    let composeFocus: FocusState<Bool>.Binding
    @Binding var showKeys: Bool
    @Binding var fontSize: Float
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RexTheme.hairline)
                .frame(height: 0.8)
            if showKeys {
                HStack(spacing: 0) {
                    FontSizeControl(fontSize: $fontSize)
                    Rectangle()
                        .fill(RexTheme.hairline)
                        .frame(width: 0.8, height: 24)
                        .padding(.trailing, 4)
                    KeyBar(controller: controller)
                }
            }
            HStack(spacing: 8) {
                Button {
                    showKeys.toggle()
                } label: {
                    Image(systemName: showKeys ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(RexTheme.text(.body))
                        .foregroundStyle(RexTheme.secondaryInk)
                        .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showKeys ? "Hide key row" : "Show key row")
                .accessibilityIdentifier("toggleKeysButton")

                TextField(prompt ?? "No pane focused", text: $composeText)
                    .font(RexTheme.monoText(.body))
                    .focused(composeFocus)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(onSend)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .glassEffect(RexTheme.glass(), in: .capsule)
                    .accessibilityIdentifier("composeField")

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(RexTheme.paper.opacity(0.55))
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(RexTheme.text(.body, weight: .bold))
                .foregroundStyle(canSend ? RexTheme.mint : RexTheme.chipInk.opacity(0.4))
                .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                .glassEffect(
                    canSend
                        ? RexTheme.glass(RexTheme.chipGlass.opacity(0.95), interactive: true)
                        : RexTheme.glass(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("sendButton")
    }
}

/// A−/A+ for the terminal grid. Pinch does the same thing on the pane itself;
/// some people would rather tap than pinch, and small screens make 9pt text
/// genuinely useful.
struct FontSizeControl: View {
    @Binding var fontSize: Float
    var onChange: ((Float) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            step("minus", delta: -1, identifier: "fontSmallerButton", label: "Smaller text")
            step("plus", delta: 1, identifier: "fontLargerButton", label: "Larger text")
        }
    }

    private func step(_ symbol: String, delta: Float, identifier: String, label: String) -> some View {
        Button {
            let next = min(max(fontSize + delta, RexTheme.minimumTerminalFontSize), RexTheme.maximumTerminalFontSize)
            fontSize = next
            onChange?(next)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(RexTheme.ink)
                .frame(width: 38, height: RexTheme.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(delta < 0 ? fontSize <= RexTheme.minimumTerminalFontSize : fontSize >= RexTheme.maximumTerminalFontSize)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
