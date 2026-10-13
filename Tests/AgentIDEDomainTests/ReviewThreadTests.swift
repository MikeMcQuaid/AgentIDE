import AgentIDEDomain
import Testing

/// Threads pasted into a prompt name each file once.
struct ReviewThreadTests {
    @Test(arguments: ["coderabbitai", "coderabbitai[bot]", "alice"])
    func `copies omit CodeRabbit boilerplate and retain the finding and replies`(author: String) {
        let finding = """
        **Do not classify a resource-only bundle by code inside a nested app.**

        If a plist-free `.bundle` contains a `.app` with a Mach-O executable, `found.find.any?` classifies
        the outer `.bundle` as a code bundle. Limit this search to code owned by the `.bundle`.
        """
        let body = """
        **🎯 Functional Correctness** | **🟠 Major** | **⚡ Quick win**

        \(finding)

        <!-- fingerprinting:phantom:poseidon:wombat -->

        <!-- cr-indicator-types:potential_issue -->

        <!-- cr-comment:v1:9d321deecae37df4136849ed -->

        <!-- This is an auto-generated comment by CodeRabbit -->
        """
        let thread = ReviewThread(
            id: "thread",
            path: "Library/Homebrew/cask/audit.rb",
            line: 687,
            isResolved: false,
            comments: [
                ReviewThreadComment(author: author, body: body),
                ReviewThreadComment(author: "alice", body: "Keep nested apps separate."),
            ],
        )
        let expected = author == "alice" ? body : finding
        #expect(thread.asText == "Library/Homebrew/cask/audit.rb:687\n"
            + author + ": " + expected + "\nalice: Keep nested apps separate.")
        #expect(ReviewThread.digest(of: [thread]) == "Library/Homebrew/cask/audit.rb\n:687 "
            + author + ": " + expected + "\nalice: Keep nested apps separate.")
        #expect(thread.comments.first?.body == body)
    }

    @Test(arguments: ["alice", "coderabbitai", "coderabbitai[bot]"])
    func `copying preserves literal code and meaningful HTML comments`(author: String) {
        let body = """
        **Preserve this markup.**

        ```html
        **🎯 Functional Correctness** | **🟠 Major** | **⚡ Quick win**
        <!-- cr-comment:v1:example -->
        ```

        `<!-- fingerprinting:example -->` must remain literal.
        <!-- Keep this explanation of the proposed fix. -->

            <!-- cr-comment:v1:indented-code -->
        """
        let thread = ReviewThread(id: "thread", path: "file", line: nil, isResolved: false, comments: [
            ReviewThreadComment(author: author, body: body),
        ])
        #expect(thread.asText == "file\n" + author + ": " + body)
    }

    @Test(arguments: [
        "**🎯 Functional Correctness** | **🟠 Major**",
        "_⚠️ Potential issue_ | _🟠 Major_",
    ], ["\n", "\r\n"])
    func `older badges and line endings preserve code indentation`(badge: String, newline: String) {
        let comment = ReviewThreadComment(author: "coderabbitai", body:
            badge + newline + newline + "    found.find.any?" + newline
                + "<!-- cr-comment:v1:tracking -->" + newline)
        #expect(comment.asText == "coderabbitai:     found.find.any?")
    }

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
