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

        return chunks(of: text).map(command(for:))
    }

    /// The commands that paste text into the attached session's
    /// active pane.
    ///
    /// A paste is not typing: it goes into a tmux buffer and is
    /// pasted from there, so tmux wraps it in bracketed paste
    /// markers when the pane's own application asked for them.
    /// Deciding that here instead was wrong, since the local
    /// terminal only learns the mode from output it has seen, and a
    /// pane attached mid-session never saw it being set: the markers
    /// went missing and the agent took a multi-line paste as several
    /// lines of typing, which is how the cursor ended up inside the
    /// pasted text rather than after it.
    ///
    /// Long text is appended to the same buffer chunk by chunk, so
    /// however many commands it takes, one paste arrives.
    public static func pasteCommands(text: String) -> [String] {
        // Whatever the local terminal wrapped it in comes off: tmux
        // adds the markers, and only when the pane wants them.
        let stripped = text
            .replacing(bracketedPasteStart, with: "")
            .replacing(bracketedPasteEnd, with: "")
        guard stripped.isEmpty == false else {
            return []
        }

        var commands = [String]()
        for (index, chunk) in chunks(of: stripped).enumerated() {
            // The first command starts the buffer and the rest add
            // to it, so one paste arrives however long it is.
            let opening = index == 0 ? "set-buffer -b " : "set-buffer -a -b "
            commands.append(opening + pasteBuffer + " -- " + quoted(chunk))
        }
        commands.append("paste-buffer -d -p -b " + pasteBuffer)
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
        "\"" + text.map(escaped).joined() + "\""
    }

    /// One character as tmux would need to read it back.
    static func escaped(_ character: Character) -> String {
        switch character {
        case "\\":
            "\\\\"

        case "\"":
            "\\\""

        case ";",
             "#",
             "~",
             "$":
            "\\" + String(character)

        case "\n":
            "\\n"

        case "\r":
            "\\r"

        case "\t":
            "\\t"

        case "\u{1B}":
            "\\e"

        default:
            controlEscape(character) ?? String(character)
        }
    }

    // MARK: Private

    /// `send-keys -H` reads bytes as hexadecimal.
    private static let hexRadix = 16

    /// The buffer a paste is staged in; it is deleted as it pastes.
    private static let pasteBuffer = "agentide-paste"

    /// What a terminal wraps a paste in when the application asked
    /// for bracketed paste.
    private static let bracketedPasteStart = "\u{1B}[200~"
    private static let bracketedPasteEnd = "\u{1B}[201~"

    /// Escaped characters per command. tmux carried 32,000 in one
    /// command in testing; half of that leaves room for the command
    /// itself and for whatever the untested ceiling really is, while
    /// keeping every ordinary paste to a single write.
    private static let escapedBudget = 16_000

    private static let asciiSpace: UInt32 = 0x20
    private static let asciiDelete: UInt32 = 0x7F

    /// The command that sends one chunk literally; `--` keeps text
    /// starting with a dash from reading as a flag.
    private static func command(for chunk: String) -> String {
        "send-keys -l -- " + quoted(chunk)
    }

    /// Splits text into pieces each of which fits one command,
    /// measured on the escaped text, since that is what tmux reads.
    private static func chunks(of text: String) -> [String] {
        var chunks = [String]()
        var chunk = ""
        var escapedLength = 0
        for character in text {
            let piece = escaped(character)
            if escapedLength + piece.count > escapedBudget, chunk.isEmpty == false {
                chunks.append(chunk)
                chunk = ""
                escapedLength = 0
            }
            chunk.append(character)
            escapedLength += piece.count
        }
        if chunk.isEmpty == false {
            chunks.append(chunk)
        }
        return chunks
    }

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
