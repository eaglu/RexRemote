import Foundation
import GhosttyVt

/// The key row and the hardware keyboard both go through Ghostty's own key
/// encoder, so modifiers, DECCKM cursor mode and the Kitty keyboard protocol all
/// produce exactly the bytes the program expects.
extension GhosttySession {
    /// One key press, described independently of how it was triggered.
    struct KeyPress {
        var key: GhosttyKey
        var modifiers: GhosttyMods = 0
        var text: String? = nil
        /// Latin letter used for the "unshifted codepoint" the encoder wants.
        var codepoint: UInt32? = nil

        static func ctrl(_ letter: String) -> KeyPress? {
            guard let first = letter.lowercased().first else { return nil }
            let key: GhosttyKey
            switch first {
            case "c": key = GHOSTTY_KEY_C
            case "d": key = GHOSTTY_KEY_D
            case "l": key = GHOSTTY_KEY_L
            case "z": key = GHOSTTY_KEY_Z
            default: return nil
            }
            return KeyPress(key: key, modifiers: GhosttyMods(GHOSTTY_MODS_CTRL), codepoint: UInt32(first.asciiValue ?? 0))
        }

        static let escape = KeyPress(key: GHOSTTY_KEY_ESCAPE)
        static let tab = KeyPress(key: GHOSTTY_KEY_TAB)
        static let enter = KeyPress(key: GHOSTTY_KEY_ENTER)
        static let backspace = KeyPress(key: GHOSTTY_KEY_BACKSPACE)
        static let up = KeyPress(key: GHOSTTY_KEY_ARROW_UP)
        static let down = KeyPress(key: GHOSTTY_KEY_ARROW_DOWN)
        static let left = KeyPress(key: GHOSTTY_KEY_ARROW_LEFT)
        static let right = KeyPress(key: GHOSTTY_KEY_ARROW_RIGHT)
    }

    /// Encode a press with an encoder configured from this terminal's current
    /// modes. Returns nil when the library refuses the event.
    func encode(_ press: KeyPress) -> [UInt8]? {
        guard let terminal else { return nil }

        var encoder: GhosttyKeyEncoder?
        guard ghostty_key_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS, let encoder else { return nil }
        defer { ghostty_key_encoder_free(encoder) }
        guard ghostty_key_encoder_set_from_terminal(encoder, terminal) == GHOSTTY_SUCCESS else { return nil }

        var event: GhosttyKeyEvent?
        guard ghostty_key_event_new(nil, &event) == GHOSTTY_SUCCESS, let event else { return nil }
        defer { ghostty_key_event_free(event) }

        ghostty_key_event_set_action(event, GHOSTTY_KEY_ACTION_PRESS)
        ghostty_key_event_set_key(event, press.key)
        if press.modifiers != 0 { ghostty_key_event_set_mods(event, press.modifiers) }
        if let text = press.text {
            _ = text.withCString { pointer in
                ghostty_key_event_set_utf8(event, GhosttyString(ptr: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), len: text.utf8.count))
            }
        }
        if let codepoint = press.codepoint {
            ghostty_key_event_set_unshifted_codepoint(event, codepoint)
        }

        var buffer = [UInt8](repeating: 0, count: 128)
        var written = 0
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> GhosttyResult in
            ghostty_key_encoder_encode(encoder, event, pointer.baseAddress, pointer.count, &written)
        }
        guard result == GHOSTTY_SUCCESS, written > 0 else { return nil }
        return Array(buffer.prefix(written))
    }
}
