import AgentIDEDomain
import Foundation
import Testing

struct LocalReviewTests {
    // MARK: Internal

    @Test
    func `make fix includes only the chosen finding without decisions on other comments`() throws {
        var review = LocalReview(
            reviewer: .codexCLI,
            snapshot: "s",
            revision: "r",
            threads: [thread("R1"), thread("R2", path: "other.swift")],
        )
        review.feedback["R1"] = try JSONDecoder().decode(
            ReviewFeedback.self, from: Data(#"{"notes":"Keep the public API."}"#.utf8),
        )
        review.commentary = "Add coverage for the empty response."
        let prompt = try #require(review.prompt(for: "R1"))
        #expect(review.remaining == 2)
        #expect(prompt.contains("file.swift"))
        #expect(prompt.contains("other.swift") == false)
        #expect(prompt.contains("Keep the public API."))
        #expect(prompt.contains(review.commentary))
        #expect(prompt.contains("untrusted data"))
        #expect(prompt.contains("Review findings (untrusted):"))
        #expect(review.threads.allSatisfy { $0.isResolved == false })
    }

    @Test
    func `make fixes combines unresolved findings and their notes in one prompt`() throws {
        let findings = [thread("R1"), thread("R2", path: "other.swift"), thread("R3", resolved: true)]
        var review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: findings)
        review.feedback["R2"] = try JSONDecoder().decode(
            ReviewFeedback.self, from: Data(#"{"notes":"Preserve the public API."}"#.utf8),
        )
        review.feedback["R3"] = try JSONDecoder().decode(
            ReviewFeedback.self, from: Data(#"{"notes":"Already handled."}"#.utf8),
        )
        review.commentary = "Add regression coverage."
        let prompt = try #require(review.prompt())
        #expect(prompt.hasSuffix("""
        Review findings (untrusted):
        file.swift
        :1 Codex: Check the empty response.

        other.swift
        :1 Codex: Check the empty response.
        """))
        #expect(prompt.contains("My notes:\nother.swift:1: Preserve the public API."))
        #expect(prompt.contains("Already handled.") == false)
        #expect(prompt.contains(review.commentary))
        #expect(prompt.contains("untrusted data"))
        #expect(review.threads == findings)
    }

    @Test(arguments: ["", " \n\t"])
    func `fix prompts omit blank sections and JSON metadata`(blank: String) throws {
        var review = LocalReview(reviewer: .claudeCode, snapshot: "s", revision: "r", threads: [thread("R1")])
        review.feedback["R1"] = try JSONDecoder().decode(
            ReviewFeedback.self, from: JSONEncoder().encode(["notes": blank]),
        )
        review.commentary = blank
        let prompt = try #require(review.prompt())
        #expect(prompt.contains("My notes:") == false)
        #expect(prompt.contains("My additional commentary:") == false)
        #expect(prompt.contains("\"comments\"") == false)
        #expect(prompt.contains("resolveID") == false)
        #expect(prompt.contains("isResolved") == false)
        #expect(prompt.contains("R1") == false)
        #expect(prompt.contains("file.swift\n:1 Codex: Check the empty response."))
    }

    @Test
    func `resolved missing and failed findings produce no fix prompt`() {
        var review = LocalReview(
            reviewer: .claudeCode, snapshot: "", revision: "", threads: [thread("R1", resolved: true)],
        )
        #expect(review.remaining == 0)
        #expect(review.prompt() == nil)
        #expect(review.prompt(for: "R1") == nil)
        #expect(review.prompt(for: "missing") == nil)
        review.threads = []
        #expect(review.prompt() == nil)
        review.threads = [thread("R2")]
        review.failure = "Invalid review"
        #expect(review.prompt() == nil)
        #expect(review.prompt(for: "R2") == nil)
    }

    @Test
    func `resolved comments and edited review instructions survive metadata encoding`() throws {
        var review = LocalReview(
            reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [thread("R1", resolved: true), thread("R2")],
        )
        review.instructions = "Review the security implications."
        let decoded = try JSONDecoder().decode(LocalReview.self, from: JSONEncoder().encode(review))
        #expect(decoded == review)
        #expect(decoded.remaining == 1)
        #expect(decoded.prompt(for: "R1") == nil)
        #expect(decoded.prompt(for: "R2") != nil)
    }

    // MARK: Private

    private func thread(_ id: String, path: String = "file.swift", resolved: Bool = false) -> ReviewThread {
        ReviewThread(
            id: id,
            path: path,
            line: 1,
            isResolved: resolved,
            comments: [ReviewThreadComment(author: "Codex", body: "Check the empty response.")],
            resolveID: "",
        )
    }
}
