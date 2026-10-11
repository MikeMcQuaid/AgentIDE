import AgentIDEDomain
import Testing

struct ReviewAnchorTests {
    @Test
    func `findings choose their hunk by new side lines with no invented anchor`() {
        let file = DiffFile(path: "file.swift", hunks: [
            DiffHunk(oldStart: 1, newStart: 1, lines: [
                DiffLine(kind: .context, content: "a"),
                DiffLine(kind: .deletion, content: "b"),
                DiffLine(kind: .addition, content: "c"),
            ]),
            DiffHunk(oldStart: 10, newStart: 10, lines: [DiffLine(kind: .addition, content: "d")]),
        ])
        #expect(file.hunkIndex(containing: 1) == 0)
        #expect(file.hunkIndex(containing: 2) == 0)
        #expect(file.hunkIndex(containing: 3) == nil)
        #expect(file.hunkIndex(containing: 10) == 1)
        #expect(file.hunkIndex(containing: 11) == nil)
        #expect(file.hunkIndex(containing: nil) == nil)
    }
}
