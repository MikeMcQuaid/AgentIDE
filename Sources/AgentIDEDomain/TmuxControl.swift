/// Builds the command lines a control mode client sends to tmux,
/// kept beside the parser so both speak the same dialect. Commands
/// omit `-t`: a control client is attached to exactly one session
/// and tmux targets its active pane.
public enum TmuxControl {
    // MARK: Public

    /// Prints the pane's whole history and visible screen with
    /// colours, to seed the local scrollback on attach.
    public static let historyCommand = "capture-pane -p -e -q -N -S -"

    /// Deepens scrollback on servers born before the config file
    /// carried the option; a long-lived server never rereads its
    /// config, and the setting only shapes panes created after it.
    public static let historyLimitCommand = "set -g history-limit 50000"

    /// The commands that deliver bytes to the attached session's
    /// active pane, in order.
    ///
    /// Text goes through `send-keys -l`, which takes literal UTF-8:
    /// `-H` names a character per hexadecimal value, not a byte, so
    /// sending a multi-byte character's bytes through it reached the
    /// agent as mojibake. Control bytes still go through `-H`, where
    /// one byte is one character anyway and escape sequences (the
    /// bracketed paste markers, Return) must arrive exactly.
    ///
    /// Text is chunked because a tmux command line has a practical
    /// length limit: past it the command is dropped in silence,
    /// which is what swallowed large pastes whole.
    public static func sendCommands(bytes: some Sequence<UInt8>) -> [String] {
        var commands = [String]()
        var text = [UInt8]()
        var control = [UInt8]()

        func flushText() {
            guard text.isEmpty == false else {
                return
            }

            // Undecodable bytes are not text; hex keeps them exact.
            if let decoded = String(bytes: text, encoding: .utf8) {
                commands += literalCommands(for: decoded)
            } else {
                commands.append(hexCommand(for: text))
            }
            text = []
        }

        func flushControl() {
            guard control.isEmpty == false else {
                return
            }

            commands.append(hexCommand(for: control))
            control = []
        }

        for byte in bytes {
            if byte < asciiSpace || byte == asciiDelete {
                flushText()
                control.append(byte)
            } else {
                flushControl()
                text.append(byte)
            }
        }
        flushText()
        flushControl()
        return commands
    }

    /// Sets the control client's size, which drives the pane's.
    public static func resizeCommand(columns: Int, rows: Int) -> String {
        "refresh-client -C " + String(columns) + "x" + String(rows)
    }

    /// A history response as terminal input: trailing blank lines
    /// go and each line needs the carriage return a terminal
    /// expects, leaving the cursor on a fresh line for live output.
    public static func seedText(lines: [String]) -> String {
        var trimmed = lines
        while trimmed.last?.isEmpty == true {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? "" : trimmed.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Internal

    /// One command per chunk of literal text, single-quoted the way
    /// tmux parses arguments; `--` keeps text that starts with a
    /// dash from reading as a flag.
    static func literalCommands(for text: String) -> [String] {
        var commands = [String]()
        var chunk = ""
        for character in text {
            chunk.append(character)
            if chunk.count >= literalChunkLength {
                commands.append("send-keys -l -- " + quoted(chunk))
                chunk = ""
            }
        }
        if chunk.isEmpty == false {
            commands.append("send-keys -l -- " + quoted(chunk))
        }
        return commands
    }

    /// A tmux argument: single quotes protect everything, and a
    /// quote of its own closes, escapes and reopens them.
    static func quoted(_ text: String) -> String {
        "'" + text.replacing("'", with: "'\\''") + "'"
    }

    // MARK: Private

    /// `send-keys -H` reads bytes as hexadecimal.
    private static let hexRadix = 16

    /// Characters per literal command. tmux drops a command line
    /// somewhere past a thousand characters without saying so, and
    /// quoting can double a chunk's length, so this stays well
    /// under half of it.
    private static let literalChunkLength = 400

    private static let asciiSpace: UInt8 = 0x20
    private static let asciiDelete: UInt8 = 0x7F

    private static func hexCommand(for bytes: [UInt8]) -> String {
        "send-keys -H " + bytes.map { String($0, radix: hexRadix) }.joined(separator: " ")
    }
}
