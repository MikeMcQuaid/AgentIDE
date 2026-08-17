import AgentIDEDomain
import Testing

/// Exercises the control mode protocol parser and command builders
/// against the shapes tmux(1) documents.
struct TmuxControlParserTests {
    @Test
    func `pane output decodes octal escapes into bytes`() {
        var parser = TmuxControlParser()
        let event = parser.parse(line: #"%output %3 hi\015\033[1m\134end"#)
        let expected: [UInt8] = Array("hi".utf8) + [0x0D, 0x1B] + Array("[1m".utf8)
            + [0x5C] + Array("end".utf8)
        #expect(event == .output(pane: "%3", bytes: expected))
    }

    @Test
    func `output without data and malformed escapes stay literal`() {
        var parser = TmuxControlParser()
        #expect(parser.parse(line: "%output %0") == .output(pane: "%0", bytes: []))
        #expect(parser.parse(line: #"%output %0 a\09"#) == .output(pane: "%0", bytes: Array(#"a\09"#.utf8)))
    }

    @Test
    func `byte lines keep split multi-byte characters intact`() {
        var parser = TmuxControlParser()
        // The two bytes are the head of a three-byte box-drawing
        // character; a string round trip would turn them into U+FFFD.
        let split: [UInt8] = Array("%output %1 ab".utf8) + [0xE2, 0x94]
        #expect(parser.parse(lineBytes: split[...]) == .output(
            pane: "%1",
            bytes: Array("ab".utf8) + [0xE2, 0x94],
        ))
        let plain = Array("%session-changed $1 work".utf8)
        #expect(parser.parse(lineBytes: plain[...]) == .notification(
            name: "session-changed",
            body: "$1 work",
        ))
    }

    @Test
    func `command responses collect lines between begin and end`() {
        var parser = TmuxControlParser()
        #expect(parser.parse(line: "%begin 1363006971 2 1") == nil)
        #expect(parser.parse(line: "first") == nil)
        #expect(parser.parse(line: "%output looks like output but is inside the block") == nil)
        let event = parser.parse(line: "%end 1363006971 2 1")
        #expect(event == .response(
            lines: ["first", "%output looks like output but is inside the block"],
            isError: false,
        ))
    }

    @Test
    func `protocol lines inside a response stay content until the numbers match`() {
        var parser = TmuxControlParser()
        #expect(parser.parse(line: "%begin 1786653489 292 1") == nil)
        // A captured pane can itself display protocol lines (a
        // terminal that showed tmux output); only the end carrying
        // this block's own command number closes it.
        #expect(parser.parse(line: "%end 1786653488 285 0") == nil)
        #expect(parser.parse(line: "%output %3 hi") == nil)
        #expect(parser.parse(line: "%begin 1786653489 291 1") == nil)
        let event = parser.parse(line: "%end 1786653489 292 1")
        #expect(event == .response(
            lines: ["%end 1786653488 285 0", "%output %3 hi", "%begin 1786653489 291 1"],
            isError: false,
        ))
        #expect(parser.parse(line: "%output %1 later") == .output(pane: "%1", bytes: Array("later".utf8)))
    }

    @Test
    func `errors and empty responses report as such`() {
        var parser = TmuxControlParser()
        #expect(parser.parse(line: "%begin 1 1 0") == nil)
        #expect(parser.parse(line: "%error 1 1 0") == .response(lines: [], isError: true))
        #expect(parser.parse(line: "%begin 1 2 0") == nil)
        #expect(parser.parse(line: "%end 1 2 0") == .response(lines: [], isError: false))
    }

    @Test
    func `exit and notifications parse with their arguments`() {
        var parser = TmuxControlParser()
        #expect(parser.parse(line: "%exit") == .exited(reason: nil))
        #expect(parser.parse(line: "%exit server exited") == .exited(reason: "server exited"))
        #expect(parser.parse(line: "%session-changed $1 work") == .notification(
            name: "session-changed",
            body: "$1 work",
        ))
        #expect(parser.parse(line: "%sessions-changed") == .notification(name: "sessions-changed", body: ""))
        #expect(parser.parse(line: "stray text") == nil)
    }

    @Test
    func `command builders emit the documented forms`() {
        // Key delivery has its own suite; this pins the rest.
        #expect(TmuxControl.resizeCommand(columns: 120, rows: 40) == "refresh-client -C 120x40")
        #expect(TmuxControl.seedText(lines: ["one", "two", "", ""]) == "one\r\ntwo\r\n")
        #expect(TmuxControl.seedText(lines: []).isEmpty)
    }
}
