@testable import AgentIDEData
import AgentIDEDomain
import Testing

// MARK: - FeedbackClipboardTests

struct FeedbackClipboardTests {
    // MARK: Internal

    @Test
    func `copy reuses a matching local review without running a tool or claiming an event`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.paths.worktreesDirectory + "/feature"
        try await world.service.git.createWorktree(repository: world.repository, branch: "feature", at: path)
        let runner = FeedbackRunner()
        let service = makeService(world, runner: runner)
        let review = try await LocalReview(
            reviewer: .codexCLI,
            snapshot: "selected diff",
            revision: service.localReviewRevision(worktreePath: path),
            threads: [AutofixFixture.thread("finding")],
        )
        service.saveLocalReview(review, worktreePath: path)
        let state = service.feedbackState(repositoryPath: world.repository.path, worktreePath: path, summary: nil)
        let event = "local:" + (review.runID ?? "")
        try service.updateFeedback(state) { value in
            value.autofixLocalReviews = true
            value.reviewer = .codexCLI
            value.handledEvents = [event]
        }
        #expect(try await service.availableFeedback(state).canCopy)
        #expect(try await service.availableFeedback(state).itemCount == 1)
        let prompt = try await service.copyFeedback(state)
        #expect(prompt.contains("Fix finding"))
        #expect(prompt.contains("run relevant local checks"))
        #expect(prompt.contains("GitHub") == false)
        let saved = service.currentFeedback(state)
        #expect(saved.handledEvents == [event])
        #expect(saved.roundsStarted == 0)
        #expect(saved.attempt == nil)
        #expect(saved.isAutomatic == false)
        #expect(saved.collection == nil)
        let calls = await runner.commands
        #expect(calls.contains { $0.contains("gh") } == false)
        #expect(calls.contains { $0.first == "sudo" } == false)
        #expect(calls.contains { $0.contains("pane") } == false)
        #expect(calls.contains { $0.joined(separator: " ").contains("codex exec") } == false)
        try await TestSupport.runGit(["commit", "--allow-empty", "-m", "Change head"], in: path)
        #expect(try await service.availableFeedback(service.currentFeedback(state)).canCopy == false)
        #expect(try await service.availableFeedback(state).itemCount == 0)
    }

    @Test
    func `empty feedback stays unavailable and only Review creates a collection`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.paths.worktreesDirectory + "/feature"
        try await world.service.git.createWorktree(repository: world.repository, branch: "feature", at: path)
        let runner = FeedbackRunner()
        let service = makeService(world, runner: runner)
        let state = service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: path, summary: nil,
        )
        try service.updateFeedback(state) { $0.autofixLocalReviews = true; $0.reviewer = .codexCLI }
        #expect(try await service.availableFeedback(service.currentFeedback(state)).canCopy == false)
        #expect(try await service.availableFeedback(state).itemCount == 0)
        await #expect(throws: (any Error).self) { try await service.copyFeedback(state) }
        #expect(service.currentFeedback(state).collection == nil)
        try await service.reviewLocalFeedback(state)
        #expect(service.currentFeedback(state).collection?.isPending == false)
        #expect(service.currentFeedback(state).collection?.failure == nil)
        #expect(service.currentFeedback(state).attempt == nil)
        #expect(try await service.availableFeedback(service.currentFeedback(state)).canCopy == false)
        #expect(try await service.availableFeedback(state).itemCount == 0)
    }

    @Test
    func `copy honours local findings resolved or reopened after collection`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.paths.worktreesDirectory + "/feature"
        try await world.service.git.createWorktree(repository: world.repository, branch: "feature", at: path)
        let service = makeService(world, runner: FeedbackRunner())
        let review = try await LocalReview(
            reviewer: .codexCLI,
            snapshot: "diff",
            revision: service.localReviewRevision(worktreePath: path),
            threads: [AutofixFixture.thread("finding")],
        )
        service.saveLocalReview(review, worktreePath: path)
        let state = service.feedbackState(repositoryPath: world.repository.path, worktreePath: path, summary: nil)
        var collection = LocalFeedbackCollection(id: "collected", revision: review.revision, configuration: "codex")
        collection.isPending = false
        collection.review = review
        try service.updateFeedback(state) { value in
            value.autofixLocalReviews = true
            value.reviewer = .codexCLI
            value.collection = collection
        }
        var resolved = review
        resolved.threads = review.threads.map { thread in
            ReviewThread(
                id: thread.id,
                path: thread.path,
                line: thread.line,
                isResolved: true,
                comments: thread.comments,
                resolveID: thread.resolveID,
            )
        }
        service.saveLocalReview(resolved, worktreePath: path)
        #expect(try await service.availableFeedback(state).canCopy == false)
        await #expect(throws: (any Error).self) { try await service.copyFeedback(state) }
        service.saveLocalReview(review, worktreePath: path)
        #expect(try await service.availableFeedback(state).canCopy)
    }

    // MARK: Private

    private func makeService(_ world: World, runner: FeedbackRunner) -> SessionService {
        SessionService(
            paths: world.paths,
            git: world.service.git,
            herdr: world.herdr,
            github: GitHubClient(runner: runner) { true },
            transcripts: world.service.transcripts,
            spool: world.service.spool,
            store: world.service.store,
            runners: [],
            processes: runner,
        )
    }
}

// MARK: - FeedbackRunner

private actor FeedbackRunner: ProcessRunner {
    var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        return ProcessResult(status: 0, standardOutput: "[]", standardError: "")
    }
}
