import Foundation

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
    /// One command carries the whole paste wherever it fits, which
    /// is nearly always: tmux accepts command lines far longer than
    /// any paste (32,000 characters verified), and an agent's
    /// interface redraws between separate writes, which is how a
    /// split paste left the cursor stranded mid-text.
    ///
    /// Text is literal UTF-8 through `send-keys -l`, since `-H`
    /// names one character per hexadecimal value rather than one
    /// byte and mangled every multi-byte character. Control bytes
    /// ride along inside the same argument as tmux's own escapes,
    /// so escape sequences and newlines arrive exactly.
    public static func sendCommands(bytes: some Sequence<UInt8>) -> [String] {
        let raw = Array(bytes)
        guard raw.isEmpty == false else {
            return []
        }

        // Undecodable bytes are not text; hexadecimal keeps them
        // exact, one character per byte being true below 0x80.
        guard let text = String(bytes: raw, encoding: .utf8) else {
            return ["send-keys -H " + raw.map { String($0, radix: hexRadix) }.joined(separator: " ")]
        }

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

    /// One tmux argument: double quotes with tmux's own escapes, so
    /// control characters travel inside the text rather than as
    /// separate commands. Everything tmux would otherwise interpret
    /// (quotes, backslashes, environment variables, home directory
    /// expansion, command separators and formats) is escaped.
    static func quoted(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\":
                escaped += "\\\\"

            case "\"":
                escaped += "\\\""

            case ";",
                 "#",
                 "~",
                 "$":
                escaped += "\\" + String(character)

            case "\n":
                escaped += "\\n"

            case "\r":
                escaped += "\\r"

            case "\t":
                escaped += "\\t"

            case "\u{1B}":
                escaped += "\\e"

            default:
                escaped += controlEscape(character) ?? String(character)
            }
        }
        return "\"" + escaped + "\""
    }

    // MARK: Private

    /// `send-keys -H` reads bytes as hexadecimal.
    private static let hexRadix = 16

    /// Characters per command. tmux carried 32,000 in one command
    /// in testing; this leaves generous room below that even when
    /// escaping quadruples a chunk, while keeping all but the
    /// largest pastes in a single write.
    private static let literalChunkLength = 4_000

    private static let asciiSpace: UInt32 = 0x20
    private static let asciiDelete: UInt32 = 0x7F

    /// Any other control character as tmux's three-digit octal
    /// escape; nil for ordinary text, which needs none.
    private static func controlEscape(_ character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              scalar.value < asciiSpace || scalar.value == asciiDelete
        else {
            return nil
        }

        return "\\" + String(format: "%03o", scalar.value)
    }
}
