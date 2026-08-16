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

    /// Types raw bytes into the attached session's active pane;
    /// `-H` sends each hexadecimal byte as a literal character.
    public static func sendKeysCommand(bytes: some Sequence<UInt8>) -> String {
        "send-keys -H " + bytes.map { String($0, radix: hexRadix) }.joined(separator: " ")
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

    // MARK: Private

    /// `send-keys -H` reads bytes as hexadecimal.
    private static let hexRadix = 16
}
