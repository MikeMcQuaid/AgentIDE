import AgentIDEDomain
import AppKit
@testable import ReviewFeature
import Testing

/// The editor's line shortcuts driven through the real text view,
/// so selection mapping and undo announcements are exercised, not
/// just the pure rules behind them.
struct EditingTextViewTests {
    // MARK: Internal

    @Test
    func `tab indents the selected lines at the file's own unit`() {
        // The unselected `keep` line is what holds the file's unit
        // steady at two spaces across the round trip.
        let view = makeView("def a\n  keep\n  one\n  two\n", language: .ruby)
        view.setSelectedRange(NSRange(location: 13, length: 10))
        view.insertTab(nil)
        #expect(view.string == "def a\n  keep\n    one\n    two\n")

        view.insertBacktab(nil)
        #expect(view.string == "def a\n  keep\n  one\n  two\n")
    }

    @Test
    func `tab at a caret types the unit and tab files keep tabs`() {
        let view = makeView("\tone\n", language: .golang)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertTab(nil)
        #expect(view.string == "\t\tone\n")
    }

    @Test
    func `the comment toggle follows the language and knows silence`() {
        let view = makeView("  one\n  two\n", language: .swift)
        view.setSelectedRange(NSRange(location: 0, length: 11))
        view.toggleComment()
        #expect(view.string == "  // one\n  // two\n")
        view.toggleComment()
        #expect(view.string == "  one\n  two\n")

        let silent = makeView("{}\n", language: .json)
        silent.setSelectedRange(NSRange(location: 0, length: 2))
        silent.toggleComment()
        #expect(silent.string == "{}\n")
    }

    @Test
    func `option arrows move the caret's line and keep it selected`() {
        let view = makeView("one\ntwo\nthree\n", language: .swift)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveLines(upwards: false)
        #expect(view.string == "two\none\nthree\n")
        #expect(view.selectedRange() == NSRange(location: 4, length: 3))

        view.moveLines(upwards: true)
        #expect(view.string == "one\ntwo\nthree\n")
        #expect(view.selectedRange() == NSRange(location: 0, length: 3))

        // The top of the file is a quiet no-op.
        view.moveLines(upwards: true)
        #expect(view.string == "one\ntwo\nthree\n")
    }

    @Test
    func `return carries the line's indentation to the new line`() {
        let view = makeView("  one\n", language: .swift)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "  one\n  \n")
        #expect(view.selectedRange() == NSRange(location: 8, length: 0))

        // A caret inside the indent carries only what is before it,
        // which leaves the split line's own indentation whole.
        let shallow = makeView("    x\n", language: .swift)
        shallow.setSelectedRange(NSRange(location: 2, length: 0))
        shallow.insertNewline(nil)
        #expect(shallow.string == "  \n    x\n")
        #expect(shallow.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test
    func `duplicating carries the caret onto the copy`() {
        let view = makeView("one\ntwo\n", language: .swift)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.duplicateLines()
        #expect(view.string == "one\none\ntwo\n")
        #expect(view.selectedRange() == NSRange(location: 5, length: 0))

        // A selection duplicates every line it touches and stays on
        // the copy.
        let block = makeView("one\ntwo", language: .swift)
        block.setSelectedRange(NSRange(location: 0, length: 7))
        block.duplicateLines()
        #expect(block.string == "one\ntwo\none\ntwo")
        #expect(block.selectedRange() == NSRange(location: 8, length: 7))
    }

    @Test
    func `deleting takes whole lines and the last line's newline too`() {
        let view = makeView("one\ntwo\nthree\n", language: .swift)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.deleteLines()
        #expect(view.string == "one\nthree\n")
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))

        let tail = makeView("one\ntwo", language: .swift)
        tail.setSelectedRange(NSRange(location: 6, length: 0))
        tail.deleteLines()
        #expect(tail.string == "one")

        let all = makeView("only\n", language: .swift)
        all.setSelectedRange(NSRange(location: 2, length: 0))
        all.deleteLines()
        #expect(all.string.isEmpty)
    }

    @Test
    func `moving the last line up preserves the missing final newline`() {
        let view = makeView("one\ntwo", language: .swift)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.moveLines(upwards: true)
        #expect(view.string == "two\none")
    }

    // MARK: Private

    private func makeView(_ text: String, language: SyntaxLanguage) -> EditingTextView {
        let view = EditingTextView()
        view.language = language
        view.string = text
        return view
    }
}
