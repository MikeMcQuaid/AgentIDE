import AgentIDEData
import AgentIDEDomain
@testable import ReviewFeature
import Testing

@MainActor
struct LocalReviewModelTests {
    // MARK: Internal

    @Test
    func `the edited review brief reaches the runner and previous instructions prefill the editor`() async {
        var savedReview = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "original", threads: [])
        savedReview.instructions = "Previous instructions"
        var supplied = ""
        let model = LocalReviewModel(
            review: savedReview,
            reviewer: .codexCLI,
            run: { _, _, instructions in
                supplied = instructions
                return savedReview
            },
            revision: { "original" },
            save: { _ in
                // The captured runner argument is the subject of this test.
            },
        )
        #expect(model.reviewInstructions == "Previous instructions")
        model.reviewInstructions += "\nCheck the authentication changes carefully."
        await model.start(files: [])
        #expect(supplied == "Previous instructions\nCheck the authentication changes carefully.")
        #expect(model.isRunning == false)
        #expect(model.reviewInstructions == supplied)
    }

    @Test
    func `a thrown review cannot prepare a fix from the previous review`() async {
        let previous = model(revision: "original").review
        let model = LocalReviewModel(
            review: previous,
            reviewer: .codexCLI,
            run: { _, _, _ in throw CancellationError() },
            revision: { "original" },
            save: { _ in Issue.record("An incomplete review must not replace the saved review") },
        )
        await model.start(files: [])
        #expect(model.isRunning == false)
        #expect(model.error != nil)
        #expect(model.canPrepare == false)
        #expect(model.review == previous)
    }

    @Test
    func `resolve and reopen update the saved local thread without claiming a fix`() async {
        let model = model(revision: "original")
        model.toggleResolved("R1")
        #expect(model.review?.threads.first?.isResolved == true)
        #expect(model.review?.remaining == 0)
        #expect(await model.prepare(threadID: "R1") { [] } == false)
        model.toggleResolved("R1")
        #expect(model.review?.threads.first?.isResolved == false)
        #expect(await model.prepare(threadID: "R1") { [] })
        #expect(model.review?.threads.first?.isResolved == false)
    }

    @Test(arguments: [nil, "R1"] as [String?])
    func `changed code cannot prepare a fix prompt`(threadID: String?) async {
        let model = model(revision: "changed")
        #expect(await model.prepare(threadID: threadID) { [] } == false)
        #expect(model.isOutdated)
        #expect(model.prompt.isEmpty)
        // A repaint of the same diff must not erase a stale HEAD verdict.
        model.update(files: [])
        #expect(model.isOutdated)
    }

    @Test(arguments: [nil, "R1"] as [String?])
    func `make fix prepares an editable prompt without a prior decision`(threadID: String?) async {
        let model = model(revision: "original")
        #expect(model.reviewInstructions == LocalReviewInput.instructions)
        #expect(await model.prepare(threadID: threadID) { [] })
        #expect(model.prompt.contains("Verify these findings"))
        model.prompt += "\nMy additional instruction."
        #expect(model.prompt.hasSuffix("My additional instruction."))
    }

    @Test(arguments: [nil, "R1"] as [String?])
    func `a changed displayed diff invalidates the review`(threadID: String?) async {
        let model = model(revision: "original")
        let files = [DiffFile(path: "changed", hunks: [])]
        #expect(await model.prepare(threadID: threadID) { files } == false)
        #expect(model.isOutdated)
    }

    @Test(arguments: [nil, "R1"] as [String?])
    func `preparing locks the review before refreshing the diff`(threadID: String?) async {
        let model = model(revision: "original")
        let prepared = await model.prepare(threadID: threadID) {
            #expect(model.isBusy)
            #expect(model.canPrepare == false)
            return []
        }
        #expect(prepared)
        #expect(model.isBusy == false)
    }

    @Test
    func `make fixes prepares all open comments without resolving them`() async {
        let model = model(revision: "original")
        model.review?.threads.append(ReviewThread(
            id: "R2",
            path: "other.swift",
            line: 2,
            isResolved: false,
            comments: [ReviewThreadComment(author: "Codex", body: "Another bug")],
            resolveID: "",
        ))
        #expect(await model.prepare { [] })
        #expect(model.prompt == model.review?.prompt())
        #expect(model.prompt.contains("file.swift\n:1 Codex: Bug"))
        #expect(model.prompt.contains("other.swift\n:2 Codex: Another bug"))
        #expect(model.review?.remaining == 2)
        model.toggleResolved("R1")
        #expect(await model.prepare { [] })
        #expect(model.prompt.contains("file.swift") == false)
        #expect(model.prompt.contains("other.swift\n:2 Codex: Another bug"))
        #expect(model.review?.remaining == 1)
        model.toggleResolved("R2")
        #expect(await model.prepare { [] } == false)
    }

    @Test
    func `a failed result persists its exchange and cannot prepare a prompt`() async {
        var review = LocalReview(reviewer: .codexCLI, snapshot: "snapshot", revision: "original", threads: [])
        review.input = "Captured input"
        review.output = "Malformed output"
        review.failure = "Invalid review"
        var saved: LocalReview?
        let model = LocalReviewModel(
            review: review,
            reviewer: .codexCLI,
            run: { _, _, _ in review },
            revision: { "original" },
            save: { saved = $0 },
        )
        #expect(model.error == "Invalid review")
        await model.start(files: [])
        #expect(saved?.input == "Captured input")
        #expect(saved?.output == "Malformed output")
        #expect(model.error == "Invalid review")
        #expect(model.canPrepare == false)
    }

    // MARK: Private

    private func model(revision: String) -> LocalReviewModel {
        let review = LocalReview(
            reviewer: .codexCLI,
            snapshot: LocalReviewInput.fingerprint(LocalReviewInput.snapshot(files: [])),
            revision: "original",
            threads: [
                ReviewThread(
                    id: "R1",
                    path: "file.swift",
                    line: 1,
                    isResolved: false,
                    comments: [ReviewThreadComment(author: "Codex", body: "Bug")],
                    resolveID: "",
                ),
            ],
        )
        return LocalReviewModel(
            review: review,
            reviewer: .codexCLI,
            run: { _, _, _ in review },
            revision: { revision },
            save: { _ in
                // Persistence is exercised in the metadata tests.
            },
        )
    }
}
