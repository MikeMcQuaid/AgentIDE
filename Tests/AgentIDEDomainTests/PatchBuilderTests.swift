import AgentIDEDomain
import Testing

struct PatchBuilderTests {
    // MARK: Internal

    @Test
    func `selected changes keep their kind and unselected additions become context`() throws {
        let selection: Set<DiffSelection> = [DiffSelection(hunkIndex: 0, lineIndex: 1)]
        let patch = try #require(PatchBuilder.reversePatch(file: Self.file, selection: selection))
        let expected = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,4 +1,3 @@
         one
        -two
         THREE
         four

        """
        #expect(patch == expected)
    }

    @Test
    func `empty selections build no patch`() {
        #expect(PatchBuilder.reversePatch(file: Self.file, selection: []) == nil)
    }

    // MARK: Private

    private static let file: DiffFile = .init(
        path: "f.txt",
        hunks: [
            DiffHunk(oldStart: 1, newStart: 1, lines: [
                DiffLine(kind: .context, content: "one"),
                DiffLine(kind: .deletion, content: "two"),
                DiffLine(kind: .addition, content: "THREE"),
                DiffLine(kind: .context, content: "four"),
            ]),
        ],
    )
}
