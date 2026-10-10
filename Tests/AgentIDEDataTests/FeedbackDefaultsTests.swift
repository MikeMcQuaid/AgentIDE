@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

struct FeedbackDefaultsTests {
    // MARK: Internal

    @Test
    func `repository defaults seed new PRs and worktrees without enabling automation`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let initial = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: world.repository.path, summary: nil,
        )
        let reviewer: AgentKind = initial.reviewer == .claudeCode ? .codexCLI : .claudeCode
        try world.service.updateFeedback(initial) { state in
            state.reviewer = reviewer
            state.reviewBot = .codeRabbit
            state.autofixLocalReviews = true
            state.autofixCI = true
            state.autofixReviews = true
            state.autofixCopilot = true
            state.isAutomatic = true
            state.pushAutomatically = true
            state.roundLimit = 3
        }
        for summary in [Self.summary(1), nil] {
            let fresh = world.service.feedbackState(
                repositoryPath: world.repository.path, worktreePath: "/new-worktree", summary: summary,
            )
            #expect(fresh.reviewer == reviewer)
            #expect(fresh.reviewBot == .codeRabbit)
            #expect(fresh.selectedSources.isEmpty)
            #expect(fresh.isAutomatic == false)
            #expect(fresh.pushAutomatically == false)
            #expect(fresh.roundLimit == 1)
        }
        let unrelated = world.service.feedbackState(repositoryPath: "/another-repo", worktreePath: nil, summary: nil)
        #expect(unrelated.reviewer == nil)
    }

    @Test
    func `reviewer edits preserve existing PR choices and other edits preserve defaults`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let first = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(1),
        )
        try world.service.updateFeedback(first) { $0.reviewer = .claudeCode }
        let second = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(2),
        )
        let unsaved = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(3),
        )
        try world.service.updateFeedback(second) { $0.reviewer = .codexCLI }
        try world.service.updateFeedback(first) { $0.pending = "Waiting" }
        #expect(world.service.currentFeedback(unsaved).reviewer == .codexCLI)
        #expect(world.service.currentFeedback(second).reviewer == .codexCLI)
        #expect(world.service.currentFeedback(first).reviewer == .claudeCode)
        try world.service.updateFeedback(unsaved) { $0.autofixLocalReviews = true }
        #expect(world.service.currentFeedback(unsaved).reviewer == .codexCLI)
    }

    @Test
    func `repository defaults survive a reload from disk`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let initial = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(1),
        )
        try world.service.updateFeedback(initial) { $0.reviewer = .codexCLI }
        let file = world.root + "/reloaded.json"
        try FileManager.default.copyItem(atPath: world.paths.metadataFile, toPath: file)
        let service = SessionService(
            paths: world.paths,
            git: world.service.git,
            herdr: world.herdr,
            github: world.service.github,
            transcripts: world.service.transcripts,
            spool: world.service.spool,
            store: MetadataStore(file: file),
            runners: [],
        )
        let reloaded = service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(2),
        )
        #expect(reloaded.reviewer == .codexCLI)
        #expect(service.currentFeedback(initial).reviewer == .codexCLI)
        #expect(reloaded.isAutomatic == false)
        #expect(reloaded.pushAutomatically == false)
    }

    @Test
    func `marking a thread first still inherits the repository defaults`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let initial = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(1),
        )
        try world.service.updateFeedback(initial) { $0.reviewer = .codexCLI }
        try world.service.pullRequests.updateAutomation(
            repositoryPath: world.repository.path,
            summary: Self.summary(2),
        ) { $0.resolutions["thread"] = PendingThreadResolution(head: "head", commentID: "comment") }
        let marked = world.service.feedbackState(
            repositoryPath: world.repository.path, worktreePath: nil, summary: Self.summary(2),
        )
        #expect(marked.reviewer == .codexCLI)
        #expect(marked.resolutions["thread"]?.commentID == "comment")
        #expect(marked.isAutomatic == false)
    }

    // MARK: Private

    private static func summary(_ number: Int) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Change",
            url: "https://github.com/owner/repo/pull/" + String(number),
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
        )
    }
}
