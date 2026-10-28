import AppKit
import TerminalUI
import Testing

struct SelectableTextViewTests {
    @Test
    func `local document links reach their action instead of opening a browser`() throws {
        let group = try #require(URL(string: "sanductor-log-group://2"))
        var clicked: URL?
        let view = SelectableTextView(text: NSAttributedString(string: "Group")) { url in
            clicked = url
            return true
        }
        #expect(view.makeCoordinator().textView(NSTextView(), clickedOnLink: group, at: 0))
        #expect(clicked == group)
    }
}
