import AgentIDEDomain
import Foundation
import Testing

/// The herdr terminal stream dialect: frame decoding and the JSON
/// command lines a controller writes.
struct HerdrTerminalTests {
    @Test
    func `frame records decode their base64 bytes`() {
        let bytes = Array("hi\u{1B}[0m".utf8)
        let line = #"{"type":"terminal.frame","seq":1,"encoding":"base64","bytes":""#
            + Data(bytes).base64EncodedString() + #"","full":true,"width":80,"height":24}"#

        #expect(HerdrTerminal.parse(line: line) == .frame(bytes: bytes))
    }

    @Test
    func `closed records carry their reason when given`() {
        #expect(HerdrTerminal.parse(line: #"{"type":"terminal.closed"}"#) == .closed(reason: nil))
        #expect(
            HerdrTerminal.parse(line: #"{"type":"terminal.closed","reason":"released"}"#)
                == .closed(reason: "released"),
        )
    }

    @Test
    func `unknown records and broken lines are dropped`() {
        #expect(HerdrTerminal.parse(line: #"{"type":"terminal.future","x":1}"#) == nil)
        #expect(HerdrTerminal.parse(line: #"{"type":"terminal.frame","bytes":"???"}"#) == nil)
        #expect(HerdrTerminal.parse(line: "not json") == nil)
        #expect(HerdrTerminal.parse(line: "") == nil)
    }

    @Test
    func `input travels as base64 so every byte arrives exactly`() throws {
        let bytes: [UInt8] = Array("pâté\r".utf8) + [0x1B, 0x5B, 0x41]

        let line = HerdrTerminal.inputCommand(bytes: bytes)

        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        #expect(object?["type"] as? String == "terminal.input")
        let encoded = try #require(object?["bytes"] as? String)
        #expect(Data(base64Encoded: encoded).map(Array.init) == bytes)
    }

    @Test
    func `resize and scroll commands carry their fields`() throws {
        let resize = try JSONSerialization.jsonObject(
            with: Data(HerdrTerminal.resizeCommand(columns: 120, rows: 40).utf8),
        ) as? [String: Any]
        #expect(resize?["type"] as? String == "terminal.resize")
        #expect(resize?["cols"] as? Int == 120)
        #expect(resize?["rows"] as? Int == 40)

        let scroll = try JSONSerialization.jsonObject(
            with: Data(HerdrTerminal.scrollCommand(upwards: true, lines: 3).utf8),
        ) as? [String: Any]
        #expect(scroll?["type"] as? String == "terminal.scroll")
        #expect(scroll?["direction"] as? String == "up")
        #expect(scroll?["lines"] as? Int == 3)
        let down = try JSONSerialization.jsonObject(
            with: Data(HerdrTerminal.scrollCommand(upwards: false, lines: 1).utf8),
        ) as? [String: Any]
        #expect(down?["direction"] as? String == "down")
    }

    @Test
    func `commands are single lines, the framing the stream needs`() {
        #expect(HerdrTerminal.inputCommand(bytes: Array("a\nb".utf8)).contains("\n") == false)
        #expect(HerdrTerminal.resizeCommand(columns: 1, rows: 1).contains("\n") == false)
        #expect(HerdrTerminal.scrollCommand(upwards: false, lines: 2).contains("\n") == false)
    }
}
