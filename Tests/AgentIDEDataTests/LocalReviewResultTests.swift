@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct LocalReviewResultTests {
    @Test(arguments: AgentKind.allCases)
    func `empty findings retain the supplied input and original CLI output`(agent: AgentKind) throws {
        let adapter: any AgentRunner = agent == .claudeCode ? ClaudeCodeRunner() : CodexRunner()
        let output = agent == .claudeCode
            ? #"{"type":"result","structured_output":{"findings":[]},"result":"No bugs found"}"#
            : #"{"findings":[]}"#
        let review = LocalReviewInput.review(
            result: ProcessResult(status: 0, standardOutput: output, standardError: "Review complete"),
            files: [],
            adapter: adapter,
            revision: "revision",
            input: "The captured diff",
        )
        #expect(review.input == "The captured diff")
        #expect(review.output == output)
        #expect(review.diagnostics == "Review complete")
        #expect(review.failure == nil)
        #expect(review.threads.isEmpty)
        #expect(review.prompt(for: "missing") == nil)
        #expect(try JSONDecoder().decode(LocalReview.self, from: JSONEncoder().encode(review)) == review)
    }

    @Test(arguments: [Int32(0), Int32(1)])
    func `invalid responses and failed processes stay inspectable`(status: Int32) {
        let review = LocalReviewInput.review(
            result: ProcessResult(status: status, standardOutput: "Invalid response", standardError: "Diagnostics"),
            files: [],
            adapter: CodexRunner(),
            revision: "revision",
            input: "The captured diff",
        )
        #expect(review.input == "The captured diff")
        #expect(review.output == "Invalid response")
        #expect(review.diagnostics == "Diagnostics")
        #expect(review.failure != nil)
        #expect(review.threads.isEmpty)
        #expect(review.prompt(for: "missing") == nil)
    }

    @Test
    func `excessive output is bounded without accepting truncated findings`() {
        let review = LocalReviewInput.review(
            result: ProcessResult(
                status: 0,
                standardOutput: String(repeating: "x", count: LocalReviewInput.byteLimit + 1),
                standardError: String(repeating: "y", count: LocalReviewInput.byteLimit + 1),
            ),
            files: [],
            adapter: CodexRunner(),
            revision: "revision",
            input: "The captured diff",
        )
        #expect(review.output == String(repeating: "x", count: LocalReviewInput.byteLimit) + "\n[Output truncated]")
        #expect(review.diagnostics
            == String(repeating: "y", count: LocalReviewInput.byteLimit) + "\n[Output truncated]")
        #expect(review.failure != nil)
        #expect(review.threads.isEmpty)
    }

    @Test
    func `a stream limit failure rejects even complete findings and a zero exit`() {
        let review = LocalReviewInput.review(
            result: ProcessResult(
                status: 0,
                standardOutput: #"{"findings":[]}"#,
                standardError: "Captured diagnostics",
                outputLimitExceeded: true,
            ),
            files: [],
            adapter: CodexRunner(),
            revision: "revision",
            input: "The captured diff",
        )
        #expect(review.failure == "The reviewer exceeded the 256 KiB output limit and was stopped.")
        #expect(review.diagnostics == "Captured diagnostics")
        #expect(review.threads.isEmpty)
    }

    @Test
    func `older saved reviews load without captured streams`() throws {
        let old = #"{"reviewer":"codex","snapshot":"s","revision":"r","threads":[],"feedback":{},"commentary":""}"#
        let review = try JSONDecoder().decode(LocalReview.self, from: Data(old.utf8))
        #expect(review.input == nil)
        #expect(review.output == nil)
        #expect(review.diagnostics == nil)
        #expect(review.failure == nil)
    }
}
