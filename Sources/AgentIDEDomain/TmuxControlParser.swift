// MARK: - TmuxControlEvent

/// One event from a tmux control mode client's output stream.
public enum TmuxControlEvent: Equatable, Sendable {
    /// A pane produced output; the octal escapes are decoded.
    case output(pane: String, bytes: [UInt8])

    /// A command finished with the lines it printed; every command
    /// sent produces exactly one response, in order.
    case response(lines: [String], isError: Bool)

    /// The client is exiting, with tmux's reason when it gave one.
    case exited(reason: String?)

    /// Any other `%` notification, name and raw arguments.
    case notification(name: String, body: String)
}

// MARK: - TmuxControlParser

/// Parses the textual protocol a `tmux -C` client emits, one line
/// at a time, as documented in tmux(1)'s CONTROL MODE section:
/// command output arrives between `%begin` and `%end` or `%error`,
/// notifications never do, and pane output escapes non-printable
/// bytes and backslash as `\xxx` octal.
public struct TmuxControlParser: Sendable {
    // MARK: Lifecycle

    /// Creates a parser expecting the start of the stream.
    public init() {
        // The first line is never inside a block.
    }

    // MARK: Public

    /// Consumes one raw line. `%output` payloads decode straight
    /// from the bytes: pane output is a byte stream whose multi-byte
    /// characters tmux may split across events, and a string round
    /// trip would replace the split points with U+FFFD.
    public mutating func parse(lineBytes: ArraySlice<UInt8>) -> TmuxControlEvent? {
        if insideBlock == false, lineBytes.starts(with: Self.outputPrefix) {
            let rest = lineBytes.dropFirst(Self.outputPrefix.count)
            guard let paneEnd = rest.firstIndex(of: Self.space) else {
                return .output(pane: String(bytes: rest, encoding: .utf8) ?? "", bytes: [])
            }

            return .output(
                pane: String(bytes: rest[..<paneEnd], encoding: .utf8) ?? "",
                bytes: Self.unescape(rest[(paneEnd + 1)...]),
            )
        }
        // Every other protocol line is ASCII; only a captured
        // content line could fail to decode, and those arrive whole.
        return parse(line: String(bytes: lineBytes, encoding: .utf8) ?? "")
    }

    /// Consumes one line and returns the event it completes, if any.
    public mutating func parse(line: String) -> TmuxControlEvent? {
        if insideBlock {
            return parseInsideBlock(line: line)
        }
        if line.hasPrefix("%begin ") {
            insideBlock = true
            blockNumber = Self.commandNumber(of: line)
            blockLines = []
            return nil
        }
        if line.hasPrefix("%output ") {
            return Self.outputEvent(line: line)
        }
        if line.hasPrefix("%exit") {
            let reason = line.dropFirst("%exit".count).trimmingCharacters(in: .whitespaces)
            return .exited(reason: reason.isEmpty ? nil : reason)
        }
        if line.hasPrefix("%") {
            let parts = line.dropFirst().split(separator: " ", maxSplits: 1)
            return .notification(
                name: parts.first.map(String.init) ?? "",
                body: parts.count > 1 ? String(parts[1]) : "",
            )
        }
        // A stray line outside any block; the protocol has none.
        return nil
    }

    // MARK: Private

    private static let octalDigits: ClosedRange<UInt8> = 0x30 ... 0x37
    private static let octalBase = 8
    private static let backslash: UInt8 = 0x5C

    /// A backslash and three octal digits.
    private static let escapeLength = 4

    private static let outputPrefix: Array = .init("%output ".utf8)
    private static let space: UInt8 = 0x20

    /// `%begin`, `%end` and `%error` lines carry time, command
    /// number and flags; the number is the second argument.
    private static let numberField = 2

    /// Whether a `%begin` block is being collected.
    private var insideBlock = false

    /// The open block's command number from its `%begin` line.
    private var blockNumber: String?

    /// The lines of the block being collected.
    private var blockLines: [String] = []

    /// Decodes one `%output pane value` line.
    private static func outputEvent(line: String) -> TmuxControlEvent {
        let rest = line.dropFirst("%output ".count)
        guard let paneEnd = rest.firstIndex(of: " ") else {
            return .output(pane: String(rest), bytes: [])
        }

        let pane = String(rest[..<paneEnd])
        return .output(pane: pane, bytes: unescape(ArraySlice(rest[rest.index(after: paneEnd)...].utf8)))
    }

    /// Whether a slice is a whole `\xxx` octal escape.
    private static func isEscape(_ escape: ArraySlice<UInt8>) -> Bool {
        escape.count == escapeLength && escape.first == backslash
            && escape.dropFirst().allSatisfy(octalDigits.contains)
    }

    /// Decodes tmux's `\xxx` octal escaping into raw bytes.
    private static func unescape(_ escaped: ArraySlice<UInt8>) -> [UInt8] {
        var bytes = [UInt8]()
        let raw = Array(escaped)
        var index = 0
        while index < raw.count {
            let escape = raw[index...].prefix(escapeLength)
            if isEscape(escape) {
                var value = 0
                for digit in escape.dropFirst() {
                    value = value * octalBase + Int(digit - octalDigits.lowerBound)
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
                index += escapeLength
            } else {
                bytes.append(raw[index])
                index += 1
            }
        }
        return bytes
    }

    /// The command number argument of a block delimiter line.
    private static func commandNumber(of line: String) -> String? {
        line.split(separator: " ").dropFirst(numberField).first.map(String.init)
    }

    private mutating func parseInsideBlock(line: String) -> TmuxControlEvent? {
        if isBlockEnd(line) {
            let lines = blockLines
            insideBlock = false
            blockNumber = nil
            blockLines = []
            return .response(lines: lines, isError: line.hasPrefix("%error "))
        }

        blockLines.append(line)
        return nil
    }

    /// Whether a line genuinely closes the open block: captured pane
    /// content can itself contain protocol-shaped lines (a terminal
    /// that displayed tmux output, say), and mistaking one for the
    /// end desynchronised the whole stream. tmux repeats the block's
    /// command number on the real end line.
    private func isBlockEnd(_ line: String) -> Bool {
        guard line.hasPrefix("%end ") || line.hasPrefix("%error ") else {
            return false
        }
        guard let blockNumber else {
            return true
        }

        return Self.commandNumber(of: line) == blockNumber
    }
}
