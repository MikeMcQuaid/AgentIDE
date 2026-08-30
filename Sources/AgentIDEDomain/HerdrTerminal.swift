import Foundation

// MARK: - HerdrTerminalEvent

/// One event from a herdr terminal control stream.
public enum HerdrTerminalEvent: Equatable, Sendable {
    /// The server rendered output; the bytes are decoded ANSI.
    case frame(bytes: [UInt8])

    /// The server closed the stream, with its reason when given.
    case closed(reason: String?)
}

// MARK: - HerdrTerminalRecord

/// One record of the stream, every field optional so unknown record
/// types and protocol additions decode rather than failing the line.
private struct HerdrTerminalRecord: Decodable {
    let type: String
    let bytes: String?
    let reason: String?
}

// MARK: - HerdrTerminalInput

/// The commands a controller writes, one JSON object per line. All
/// fields ride one struct because an encoder cannot be handed a
/// union, and `nil` fields are simply absent from the line. The
/// fields are read only by synthesised Encodable conformance, which
/// periphery's assign-only check does not see.
private struct HerdrTerminalInput: Encodable {
    // periphery:ignore
    let type: String
    // periphery:ignore
    var bytes: String?
    // periphery:ignore
    var cols: Int?
    // periphery:ignore
    var rows: Int?
    // periphery:ignore
    var direction: String?
    // periphery:ignore
    var lines: Int?
}

// MARK: - HerdrTerminal

/// Speaks the newline-delimited JSON protocol of `herdr terminal
/// session control`: `terminal.frame` records carrying base64 ANSI
/// bytes come out, and input, resize and scroll commands go back in.
public enum HerdrTerminal {
    // MARK: Public

    /// How much of a paste goes to the pane at once, and the gap
    /// between pieces. An agent in raw mode has cleared `IMAXBEL`, and
    /// macOS's tty driver answers an input queue overflowing in that
    /// state by flushing the whole queue: a large paste written at
    /// once lost its head, every terminal paces pastes for this, and
    /// the queue is a kibibyte deep. `cat` drained a whole paste
    /// unpaced; an agent redrawing between reads does not.
    public static let inputChunkBytes = 1_024

    /// The pause between two pieces of one paste.
    public static let inputChunkDelayMilliseconds = 8

    /// Parses one line of the stream. Unknown record types answer
    /// nil, so additions to the protocol never break the pane.
    public static func parse(line: String) -> HerdrTerminalEvent? {
        guard let record = try? JSONDecoder().decode(HerdrTerminalRecord.self, from: Data(line.utf8)) else {
            return nil
        }

        switch record.type {
        case "terminal.frame":
            guard let encoded = record.bytes, let decoded = Data(base64Encoded: encoded) else {
                return nil
            }

            return .frame(bytes: Array(decoded))

        case "terminal.closed":
            return .closed(reason: record.reason)

        default:
            return nil
        }
    }

    /// The command that writes bytes to the pane's terminal, sent as
    /// base64 so escape sequences and multi-byte characters arrive
    /// exactly.
    public static func inputCommand(bytes: some Sequence<UInt8>) -> String {
        encode(HerdrTerminalInput(type: "terminal.input", bytes: Data(bytes).base64EncodedString()))
    }

    /// The commands that write bytes to the pane's terminal, in order,
    /// none larger than `inputChunkBytes`.
    public static func inputCommands(bytes: [UInt8]) -> [String] {
        stride(from: 0, to: bytes.count, by: inputChunkBytes).map { start in
            inputCommand(bytes: bytes[start ..< min(start + inputChunkBytes, bytes.count)])
        }
    }

    /// The command that sets the controller's viewport size, which
    /// drives the pane's.
    public static func resizeCommand(columns: Int, rows: Int) -> String {
        encode(HerdrTerminalInput(type: "terminal.resize", cols: columns, rows: rows))
    }

    /// The command that scrolls the attached viewport; herdr owns
    /// the scrollback, so the wheel pages through it server-side.
    public static func scrollCommand(upwards: Bool, lines: Int) -> String {
        encode(HerdrTerminalInput(type: "terminal.scroll", direction: upwards ? "up" : "down", lines: lines))
    }

    // MARK: Private

    /// One command as its line. Encoding these fixed shapes cannot
    /// fail; an empty line is ignored by the server regardless.
    private static func encode(_ input: HerdrTerminalInput) -> String {
        String(bytes: (try? JSONEncoder().encode(input)) ?? Data(), encoding: .utf8) ?? ""
    }
}
