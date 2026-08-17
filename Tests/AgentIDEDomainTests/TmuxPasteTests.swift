import AgentIDEDomain
import Testing

// MARK: - TmuxPasteTests

/// Pins how a paste reaches an agent. All three failures here were
/// real: hexadecimal delivery mangled every multi-byte character, an
/// over-long command line was dropped by tmux without a word, and a
/// paste split across commands left the cursor stranded mid-text
/// because the agent redrew between writes. The property that
/// matters is that the commands reconstruct the pasted bytes
/// exactly, so these tests decode them back.
struct TmuxPasteTests {
    // MARK: Internal

    @Test
    func `every paste reconstructs byte for byte`() {
        let cases = [
            "héllo 🙂",
            "don't",
            "plain ascii",
            "line one\nline two\r\n",
            "\u{1B}[200~pasted\u{1B}[201~",
            "tabs\tand $HOME and ~user and #hash and ;semi and \\slash",
            "\u{1}\u{7F} control bytes",
            String(repeating: "x", count: 9_000),
            String(repeating: "é", count: 3_000),
            "-- leading dashes",
        ]
        for text in cases {
            let bytes = Array(text.utf8)
            #expect(Self.bytes(from: TmuxControl.sendCommands(bytes: bytes)) == bytes, "\(text.prefix(20))")
        }
    }

    @Test
    func `an ordinary paste travels as a single command`() {
        // Splitting a paste is what stranded the cursor, so one
        // write is the point, markers and newlines included.
        let paste = "\u{1B}[200~a multi-line\npaste with 🙂\u{1B}[201~"
        #expect(TmuxControl.sendCommands(bytes: Array(paste.utf8)).count == 1)
    }

    @Test
    func `text is literal and control characters ride with it`() {
        #expect(TmuxControl.sendCommands(bytes: Array("héllo 🙂".utf8)) == ["send-keys -l -- \"héllo 🙂\""])
        #expect(TmuxControl.sendCommands(bytes: [0x68, 0x0D]) == ["send-keys -l -- \"h\\r\""])
        #expect(TmuxControl.sendCommands(bytes: Array("a\u{1B}b".utf8)) == ["send-keys -l -- \"a\\eb\""])
        #expect(TmuxControl.sendCommands(bytes: []).isEmpty)
    }

    @Test
    func `a paste beyond one command still splits rather than being dropped`() {
        let commands = TmuxControl.sendCommands(bytes: Array(String(repeating: "x", count: 9_000).utf8))
        #expect(commands.count > 1)
        // Comfortably inside what tmux carried in testing.
        #expect(commands.allSatisfy { $0.count < 32_000 })
    }

    // MARK: Private

    /// The bytes a tmux server would deliver for these commands,
    /// undoing the parser's own quoting and escapes.
    private static func bytes(from commands: [String]) -> [UInt8] {
        var result = [UInt8]()
        for command in commands {
            if let literal = command.after("send-keys -l -- ") {
                result += Array(unescaped(String(literal.dropFirst().dropLast())).utf8)
            } else if let hex = command.after("send-keys -H ") {
                result += hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            }
        }
        return result
    }

    /// Undoes tmux's double-quoted escapes.
    private static func unescaped(_ argument: String) -> String {
        var result = ""
        var characters = Array(argument)
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                result.append(characters[index])
                index += 1
                continue
            }

            let next = characters[index + 1]
            switch next {
            case "n":
                result.append("\n")

            case "r":
                result.append("\r")

            case "t":
                result.append("\t")

            case "e":
                result.append("\u{1B}")

            case "0" ... "7":
                let digits = String(characters[(index + 1) ... min(index + 3, characters.count - 1)])
                if let value = UInt32(digits, radix: 8), let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                }
                index += 4
                continue

            default:
                result.append(next)
            }
            index += 2
        }
        return result
    }
}

private extension String {
    /// The remainder after a prefix, nil when it is not there.
    func after(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
