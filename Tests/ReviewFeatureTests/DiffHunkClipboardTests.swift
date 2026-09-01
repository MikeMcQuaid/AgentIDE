import Foundation
@testable import ReviewFeature
import Testing

/// The selectable hunk's copy, which strips each line's gutter so a
/// drag copy pastes as code.
struct DiffHunkClipboardTests {
    @Test
    func `a copy spanning lines drops every gutter prefix`() {
        // Gutter of four: "NN± ".
        let text = "10+ let a = 1\n11+ let b = 2\n12  end\n"
        let all = DiffHunkClipboard.stripped(text, selection: NSRange(location: 0, length: 36), gutterLength: 4)
        #expect(all == "let a = 1\nlet b = 2\nend\n")
    }

    @Test
    func `a partial selection keeps only what it touched of the code`() {
        let text = "10+ let a = 1\n11+ let b = 2\n"
        // From inside `a = 1` to inside the next line's code.
        let slice = DiffHunkClipboard.stripped(text, selection: NSRange(location: 8, length: 15), gutterLength: 4)
        #expect(slice == "a = 1\nlet b")
    }

    @Test
    func `a selection entirely inside a gutter copies nothing`() {
        let text = "10+ let a = 1\n"
        let none = DiffHunkClipboard.stripped(text, selection: NSRange(location: 0, length: 3), gutterLength: 4)
        #expect(none.isEmpty)
    }
}
