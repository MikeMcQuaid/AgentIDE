import AppKit
@testable import TerminalUI
import Testing

/// The messages pane's one attributed log, newest first, links live.
struct ErrorLogTextTests {
    @Test
    func `the log reads newest first with times in front`() throws {
        let entries = [
            ErrorLog.Entry(id: 1, date: Date(timeIntervalSince1970: 0), message: "First note", isError: false),
            ErrorLog.Entry(id: 2, date: Date(timeIntervalSince1970: 60), message: "Then a failure", isError: true),
        ]
        let text = ErrorLogText.attributed(entries).string
        let first = text.range(of: "Then a failure")
        let second = text.range(of: "First note")
        #expect(first != nil && second != nil)
        #expect(try #require(first?.lowerBound) < #require(second?.lowerBound))
    }

    @Test
    func `web links in messages are live`() {
        let entries = [
            ErrorLog.Entry(id: 1, date: .now, message: "See https://example.com/run for the log", isError: false),
        ]
        let text = ErrorLogText.attributed(entries)
        var found = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil {
                found = true
            }
        }
        #expect(found)
    }
}
