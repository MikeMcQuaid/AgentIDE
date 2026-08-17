import AgentIDEDomain
import Testing

// MARK: - TmuxPasteTests

/// Pins how a paste reaches an agent. Both failures here were real:
/// hexadecimal delivery mangled every multi-byte character, and one
/// long command line was dropped by tmux without a word, so large
/// pastes vanished entirely. The property that matters is that the
/// commands reconstruct the pasted bytes exactly, whatever the
/// chunking, so these tests decode them back.
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
            String(repeating: "x", count: 3_000),
            String(repeating: "é", count: 900),
            "-- leading dashes",
        ]
        for text in cases {
            let bytes = Array(text.utf8)
            #expect(Self.bytes(from: TmuxControl.sendCommands(bytes: bytes)) == bytes, "\(text.prefix(20))")
        }
    }

    @Test
    func `text goes literally and control bytes go exactly`() {
        #expect(TmuxControl.sendCommands(bytes: Array("héllo 🙂".utf8)) == ["send-keys -l -- 'héllo 🙂'"])
        #expect(TmuxControl.sendCommands(bytes: Array("don't".utf8)) == ["send-keys -l -- 'don'\\''t'"])
        #expect(TmuxControl.sendCommands(bytes: [0x68, 0x0D]) == ["send-keys -l -- 'h'", "send-keys -H d"])
    }

    @Test
    func `a long paste splits into commands tmux will accept`() {
        let commands = TmuxControl.sendCommands(bytes: Array(String(repeating: "x", count: 3_000).utf8))
        #expect(commands.count > 1)
        // tmux drops a command line somewhere past a thousand
        // characters without reporting it.
        #expect(commands.allSatisfy { $0.count < 1_000 })
    }

    // MARK: Private

    /// The bytes a tmux server would deliver for these commands.
    private static func bytes(from commands: [String]) -> [UInt8] {
        var result = [UInt8]()
        for command in commands {
            if let literal = command.after("send-keys -l -- ") {
                result += Array(unquoted(literal).utf8)
            } else if let hex = command.after("send-keys -H ") {
                result += hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            }
        }
        return result
    }

    /// Undoes the single quoting tmux's parser would undo.
    private static func unquoted(_ argument: String) -> String {
        String(argument.dropFirst().dropLast()).replacing("'\\''", with: "'")
    }
}

private extension String {
    /// The remainder after a prefix, nil when it is not there.
    func after(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
