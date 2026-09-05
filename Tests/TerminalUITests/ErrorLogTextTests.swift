import AppKit
@testable import TerminalUI
import Testing

/// The messages pane's one attributed log, newest first, links live.
struct ErrorLogTextTests {
    @Test
    func `the log reads newest first with times in front`() throws {
        let entries = [
            ErrorLog.Entry(
                id: 1,
                date: Date(timeIntervalSince1970: 0),
                message: "First note",
                isError: false,
                repository: nil,
            ),
            ErrorLog.Entry(
                id: 2,
                date: Date(timeIntervalSince1970: 60),
                message: "Then a failure",
                isError: true,
                repository: nil,
            ),
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
            ErrorLog.Entry(
                id: 1,
                date: .now,
                message: "See https://example.com/run for the log",
                isError: false,
                repository: nil,
            ),
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

    @Test
    func `an identifier is monospaced and its repository bold`() throws {
        let entries = [
            ErrorLog.Entry(
                id: 1,
                date: .now,
                message: "brew: Pushed `non-capturing-regexp-groups`.",
                isError: false,
                repository: "brew",
            ),
        ]
        let text = ErrorLogText.attributed(entries)

        // The backticks are markup, not text.
        #expect(text.string.contains("`") == false)
        #expect(text.string.contains("brew: Pushed non-capturing-regexp-groups."))

        let branch = try #require(text.string.range(of: "non-capturing-regexp-groups"))
        let monospaced = text.attribute(
            .font,
            at: NSRange(branch, in: text.string).location,
            effectiveRange: nil,
        ) as? NSFont
        #expect(monospaced?.fontName.contains("Mono") == true)

        let name = try #require(text.string.range(of: "brew"))
        let bold = text.attribute(
            .font,
            at: NSRange(name, in: text.string).location,
            effectiveRange: nil,
        ) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test
    func `a line names its repository and its branch in front`() {
        ErrorLog.shared.clear()
        ErrorLog.shared.note("pushed", about: "brew", branch: "more_deprecations")
        ErrorLog.shared.report("rebasing failed", about: "brew")
        let entries = ErrorLog.shared.entries

        #expect(entries.first?.message == "brew: `more_deprecations`: pushed")
        #expect(entries.first?.repository == "brew")
        // A message about no branch in particular names only the
        // repository, and a repeated name is said once.
        #expect(entries.last?.message == "brew: rebasing failed")
        ErrorLog.shared.note("brew: already named", about: "brew", branch: "main")
        #expect(ErrorLog.shared.entries.last?.message == "brew: already named")
        ErrorLog.shared.clear()
    }
}
