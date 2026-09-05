/// What a modified arrow key means to a program that never asked for
/// anything better.
///
/// SwiftTerm now reports Option-arrows through the kitty keyboard
/// protocol's encoding (`ESC [ 1 ; 3 D`), which agents understand
/// because they turn that protocol on. A shell has not: zsh reads as
/// far as `ESC [ 1`, finds nothing bound, and types the rest of the
/// sequence into the line, so Option-left showed `;3D` instead of
/// moving a word. Terminals have sent Option-left and Option-right as
/// meta-b and meta-f since long before that, which readline, zsh and
/// friends all bind, and meta plus the plain sequence for the others.
public enum TerminalKeys {
    // MARK: Public

    /// The four arrows, named as the keyboard names them.
    public enum Arrow: Sendable {
        case left
        case right
        case upward
        case downward
    }

    /// The bytes Option and one arrow send.
    public static func optionArrow(_ arrow: Arrow, applicationCursor: Bool) -> [UInt8] {
        switch arrow {
        case .left:
            [escape, UInt8(ascii: "b")]

        case .right:
            [escape, UInt8(ascii: "f")]

        case .upward:
            [escape] + cursor(applicationCursor, final: "A")

        case .downward:
            [escape] + cursor(applicationCursor, final: "B")
        }
    }

    // MARK: Private

    private static let escape: UInt8 = 0x1B

    /// One cursor-key sequence, in whichever of the two forms the
    /// program has asked for.
    private static func cursor(_ applicationCursor: Bool, final: Unicode.Scalar) -> [UInt8] {
        [escape, UInt8(ascii: applicationCursor ? "O" : "["), UInt8(ascii: final)]
    }
}
