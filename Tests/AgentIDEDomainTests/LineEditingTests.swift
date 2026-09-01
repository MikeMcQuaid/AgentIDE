@testable import AgentIDEDomain
import Testing

/// The pure line edits behind the editor's shortcuts: comment
/// toggling, indentation and moving lines.
struct LineEditingTests {
    @Test
    func `each language knows its line comment, or that it has none`() {
        #expect(LineEditing.commentPrefix(for: .swift) == "//")
        #expect(LineEditing.commentPrefix(for: .typescript) == "//")
        #expect(LineEditing.commentPrefix(for: .ruby) == "#")
        #expect(LineEditing.commentPrefix(for: .shell) == "#")
        #expect(LineEditing.commentPrefix(for: .yaml) == "#")
        #expect(LineEditing.commentPrefix(for: .gitMessage) == "#")
        #expect(LineEditing.commentPrefix(for: .json) == nil)
        #expect(LineEditing.commentPrefix(for: .markdown) == nil)
        #expect(LineEditing.commentPrefix(for: nil) == nil)
    }

    @Test
    func `commenting lands after the shallowest indentation and toggles off cleanly`() {
        let block = ["    one", "        two", "    three"]
        let commented = LineEditing.toggledComment(block, prefix: "//")
        #expect(commented == ["    // one", "    //     two", "    // three"])
        #expect(LineEditing.toggledComment(commented, prefix: "//") == block)
    }

    @Test
    func `a mixed block comments everything and blank lines are left alone`() {
        let block = ["// done", "todo", ""]
        let commented = LineEditing.toggledComment(block, prefix: "//")
        #expect(commented == ["// // done", "// todo", ""])

        // A prefix without the space it usually rides with still
        // uncomments.
        #expect(LineEditing.toggledComment(["#tight", "# loose"], prefix: "#") == ["tight", "loose"])
    }

    @Test
    func `indenting adds the unit and dedenting takes at most one`() {
        #expect(LineEditing.indented(["a", "  b", ""], unit: "  ") == ["  a", "    b", ""])
        #expect(LineEditing.dedented(["  a", "    b", "c", ""], unit: "  ") == ["a", "  b", "c", ""])
        // A partial indent dedents what is there rather than eating
        // the line's first characters.
        #expect(LineEditing.dedented([" a"], unit: "  ") == ["a"])
        #expect(LineEditing.dedented(["\tb", "c"], unit: "\t") == ["b", "c"])
    }

    @Test
    func `moving lines swaps them over a boundary and stops at the edges`() {
        let lines = ["one", "two", "three", "four"]
        let raised = LineEditing.moved(lines, in: 2 ..< 3, upwards: true)
        #expect(raised?.lines == ["one", "three", "two", "four"])
        #expect(raised?.range == 1 ..< 2)

        let lowered = LineEditing.moved(lines, in: 1 ..< 3, upwards: false)
        #expect(lowered?.lines == ["one", "four", "two", "three"])
        #expect(lowered?.range == 2 ..< 4)

        #expect(LineEditing.moved(lines, in: 0 ..< 1, upwards: true) == nil)
        #expect(LineEditing.moved(lines, in: 3 ..< 4, upwards: false) == nil)
    }

    @Test
    func `the indentation unit follows the file, tabs first`() {
        #expect(LineEditing.indentationUnit(of: ["def a", "\tone"]) == "\t")
        #expect(LineEditing.indentationUnit(of: ["def a", "  one", "    two"]) == "  ")
        #expect(LineEditing.indentationUnit(of: ["func a() {", "    one", "        two"]) == "    ")
        // A flat file says nothing, so two spaces stand in.
        #expect(LineEditing.indentationUnit(of: ["a", "b"]) == "  ")
        // Levels that share no step fall back rather than indenting
        // by a single space.
        #expect(LineEditing.indentationUnit(of: [" odd", "  even"]) == "  ")
    }
}
