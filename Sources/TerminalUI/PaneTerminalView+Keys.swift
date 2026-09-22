import AgentIDEDomain
import AppKit

/// What a key means to a local shell pane, which sees the keyboard
/// modes its own PTY set and has asked for nothing better. Split
/// from the view for length.
extension PaneTerminalView {
    /// Sends Option and an arrow as terminals always have, and the
    /// numeric keypad as the numbers it is labelled with, for a
    /// local shell that never asked for the kitty keyboard protocol:
    /// SwiftTerm encodes the arrows the way that protocol does
    /// whether or not anything turned it on, and a shell typed the
    /// tail of the sequence into the line rather than moving a word.
    /// The keypad it answers as a VT does, since zsh asks for
    /// application keypad mode at every prompt, so the 5 arrived as
    /// `ESC O u` and a Mac has no Num Lock to turn that off with.
    /// Fed by the coordinator's event monitor, since `keyDown` is
    /// not overridable either; nil means the pane consumed it.
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard isHerdrBacked == false,
              unsafe window?.firstResponder === self,
              getTerminal().keyboardEnhancementFlags.isEmpty,
              event.modifierFlags.isDisjoint(with: [.command, .control])
        else {
            return event
        }

        if event.modifierFlags.contains(.option) {
            guard let arrow = Self.arrow(of: event) else {
                return event
            }

            send(TerminalKeys.optionArrow(arrow, applicationCursor: getTerminal().applicationCursor))
            return nil
        }

        guard let text = Self.numericPadText(of: event) else {
            return event
        }

        send(txt: text)
        return nil
    }

    // MARK: Private

    /// The characters a keypad key can type: space through tilde.
    private static let printable: ClosedRange<UInt32> = 0x20 ... 0x7E

    /// Which arrow an event is, if it is one.
    private static func arrow(of event: NSEvent) -> TerminalKeys.Arrow? {
        guard let key = event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) })
        else {
            return nil
        }

        switch key {
        case NSLeftArrowFunctionKey:
            return .left

        case NSRightArrowFunctionKey:
            return .right

        case NSUpArrowFunctionKey:
            return .upward

        case NSDownArrowFunctionKey:
            return .downward

        default:
            return nil
        }
    }

    /// What a numeric keypad key types, for the keys that type
    /// anything: the digits, the separator and the operators, whose
    /// characters are their labels because a Mac keypad is always
    /// numeric. Enter and Clear report control characters and keep
    /// the sequences SwiftTerm sends for them, and every other key
    /// the keypad flag covers (the arrows, Home, Page Up) reports a
    /// function key well outside this range.
    private static func numericPadText(of event: NSEvent) -> String? {
        guard event.modifierFlags.contains(.numericPad), let text = event.characters,
              text.isEmpty == false,
              text.unicodeScalars.allSatisfy({ printable.contains($0.value) })
        else {
            return nil
        }

        return text
    }
}
