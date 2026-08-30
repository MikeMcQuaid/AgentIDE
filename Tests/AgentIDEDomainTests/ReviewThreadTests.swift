import AgentIDEDomain
import Testing

/// Threads pasted into a prompt name each file once.
struct ReviewThreadTests {
    @Test
    func `a digest names each file once above its threads`() {
        let threads = [
            ReviewThread(id: "1", path: "a.swift", line: 12, isResolved: false, comments: [
                ReviewThreadComment(author: "alice", body: "Rename this"),
                ReviewThreadComment(author: "bob", body: "Done"),
            ]),
            ReviewThread(id: "2", path: "b.swift", line: nil, isResolved: false, comments: [
                ReviewThreadComment(author: "alice", body: "Whole file"),
            ]),
            ReviewThread(id: "3", path: "a.swift", line: 40, isResolved: false, comments: [
                ReviewThreadComment(author: "alice", body: "And here"),
            ]),
        ]
        #expect(ReviewThread.digest(of: threads) == """
        a.swift
        :12 alice: Rename this
        bob: Done
        :40 alice: And here

        b.swift
        alice: Whole file
        """)
    }
}
