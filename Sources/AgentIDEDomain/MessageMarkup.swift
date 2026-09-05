/// The little markup the messages pane understands. Every message
/// this app writes names identifiers the way the launch progress
/// already does, in backticks, and the pane draws those monospaced
/// so a branch, a ref or a command is told from the prose around it.
public enum MessageMarkup {
    // MARK: Public

    /// The message as it is shown, with the backticks taken out, and
    /// where each span they marked ended up. A backtick with no
    /// partner is prose like any other character.
    public static func rendered(_ message: String) -> (text: String, code: [Range<String.Index>]) {
        var text = ""
        var code = [Range<String.Index>]()
        var rest = Substring(message)
        while let opening = rest.firstIndex(of: tick) {
            let after = rest.index(after: opening)
            guard let closing = rest[after...].firstIndex(of: tick) else {
                break
            }

            text += rest[..<opening]
            let start = text.endIndex
            text += rest[after ..< closing]
            code.append(start ..< text.endIndex)
            rest = rest[rest.index(after: closing)...]
        }
        text += rest
        return (text, code)
    }

    // MARK: Private

    private static let tick: Character = "`"
}
