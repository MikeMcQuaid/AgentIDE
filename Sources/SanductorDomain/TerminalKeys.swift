/// Shell arrow bindings: meta-b and meta-f move a word, while vertical
/// arrows send meta followed by the cursor sequence the shell requested.
public enum TerminalKeys {
    // MARK: Public

    /// The four arrows and their terminal sequence's final character.
    public enum Arrow: String, Sendable {
        case left = "D"
        case right = "C"
        case upward = "A"
        case downward = "B"
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
