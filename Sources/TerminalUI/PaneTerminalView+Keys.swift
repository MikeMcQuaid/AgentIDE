import AppKit
import SanductorDomain

/// Key routing for local shells and herdr-backed agents.
extension PaneTerminalView {
    /// Keeps agent modifiers and traditional shell bindings when the
    /// local terminal has no keyboard protocol. Nil consumes the event.
    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard unsafe window?.firstResponder === self,
              keyboardEnhancementFlags.isEmpty,
              event.modifierFlags.isDisjoint(with: [.command, .control])
        else {
            return event
        }

        if event.modifierFlags.contains(.option) {
            guard let arrow = Self.arrow(of: event) else {
                return event
            }

            if isHerdrBacked {
                guard event.modifierFlags.contains(.shift) == false else {
                    return event
                }

                // herdr omits the agent's keyboard modes; SwiftTerm applies shell bindings without them.
                send(txt: "\u{1B}[1;3\(arrow.rawValue)")
                return nil
            }

            switch arrow {
            case .left,
                 .right:
                send(TerminalKeys.optionArrow(arrow, applicationCursor: false))

            case .upward:
                send(txt: "\u{1B}")
                sendKeyUp()

            case .downward:
                send(txt: "\u{1B}")
                sendKeyDown()
            }
            return nil
        }

        guard isHerdrBacked == false,
              event.modifierFlags.contains(.shift) == false,
              let text = Self.numericPadText(of: event)
        else {
            return event
        }

        selectNone()
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
