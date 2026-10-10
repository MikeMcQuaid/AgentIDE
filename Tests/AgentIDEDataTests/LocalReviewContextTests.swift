@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct LocalReviewContextTests {
    @Test
    func `local findings retain bounded reviewed code through persistence`() throws {
        let file = DiffFile(path: "file.swift", hunks: [
            DiffHunk(
                oldStart: 1,
                newStart: 1,
                lines: (1 ... 20).map { DiffLine(kind: .addition, content: "line " + String($0)) },
            ),
        ])
        let review = LocalReviewInput.review(
            result: ProcessResult(
                status: 0,
                standardOutput: #"{"findings":[{"path":"file.swift","line":10,"title":"Bug","body":"Fix it"}]}"#,
                standardError: "",
            ),
            files: [file],
            adapter: CodexRunner(),
            revision: "revision",
            input: "input",
        )
        let saved = try JSONDecoder().decode(LocalReview.self, from: JSONEncoder().encode(review))
        let context = try #require(saved.threads.first?.codeContext)
        #expect(context.contains("\t10\t+line 10"))
        #expect(context.contains("line 1\n") == false)
        #expect(context.contains("line 20") == false)
        #expect(context.split(separator: "\n").count == 8)
    }

    @Test
    func `file level and deleted findings retain honest code context`() {
        let file = DiffFile(path: "gone.swift", hunks: [
            DiffHunk(oldStart: 4, newStart: 3, lines: [DiffLine(kind: .deletion, content: "removed()")]),
        ])
        #expect(LocalReviewInput.context(file: file, line: nil) == "gone.swift\n4\t\t-removed()")
        #expect(LocalReviewInput.context(file: DiffFile(path: "empty", hunks: []), line: nil) == nil)
    }
}
