@testable import AgentIDEData
import AgentIDEDomain
import Foundation

actor AutofixFixture {
    // MARK: Lifecycle

    init() throws {
        directory = try TestSupport.temporaryDirectory("autofix")
        store = MetadataStore(file: directory + "/state.json")
        store.update { value in
            value.pullRequestAutomation[Self.key] = PullRequestAutomation(
                repositoryPath: "/repo",
                number: 1,
                url: Self.key,
            )
        }
    }

    // MARK: Internal

    struct State {
        var head = "head"
        var freshHead = "head"
        var localHead = "head"
        var activity: AgentActivity = .done
        var hasSession = true
        var checksComplete = true
        var comments: [ReviewThread] = []
        // Nil reuses the initial snapshot; empty explicitly removes its comments.
        // swiftlint:disable:next discouraged_optional_collection
        var freshComments: [ReviewThread]?
        var reviewEvents: [ReviewComment] = []
        // Nil keeps the first reading.
        // swiftlint:disable:next discouraged_optional_collection
        var freshReviewEvents: [ReviewComment]?
        var requestedBots: [ReviewBot] = []
        var writers: Set<String> = []
        // Nil reuses permissions; an empty set revokes them.
        // swiftlint:disable:next discouraged_optional_collection
        var freshWriters: Set<String>?
        var localReview: LocalReview?
        var localCollection: LocalFeedbackCollection?
        var result: AutofixResult?
        var failPush = false
        var failResolution = false
        var deliveries: [AutofixAttempt] = []
        var prompts: [String] = []
        var resolutions: [String] = []
        var pushes: [String] = []
    }

    static let key = "https://github.com/owner/repo/pull/1"

    let directory: String
    let store: MetadataStore
    var state: State = .init()

    static func thread(
        _ id: String,
        comment: String = "comment",
        author: String = "human",
        type: String = "User",
        context: String? = nil,
    ) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "file.swift",
            line: 1,
            isResolved: false,
            comments: [ReviewThreadComment(author: author, body: "Fix " + id, id: comment, authorType: type)],
            codeContext: context,
        )
    }

    func update(_ change: @Sendable (inout State) -> Void) {
        change(&state)
    }

    func driver() -> AutofixDriver {
        AutofixDriver(
            summary: { _, fresh in await self.summary(fresh: fresh) },
            threads: { _, fresh in await self.threads(fresh: fresh) },
            writers: { _, _, fresh in await self.writers(fresh: fresh) },
            localReview: { _ in await self.state.localReview },
            target: { _, _ in await self.target() },
            head: { _ in await self.state.localHead },
            collect: { _, _, _ in await self.state.localCollection },
            reviewComments: { _, fresh in await self.reviewEvents(fresh: fresh) },
            requestBot: { _, bot in await self.request(bot) },
            ready: { _, head in await self.ready(head: head) },
            deliver: { attempt, prompt in await self.deliver(attempt, prompt: prompt) },
            result: { _ in await self.state.result },
            push: { _, _, commit in try await self.push(commit) },
            resolve: { _, id in try await self.resolve(id) },
        )
    }

    func complete(addressed: Set<String> = [], commit: String = "fixed") {
        guard let attempt = state.deliveries.last else {
            return
        }

        state.localHead = commit
        state.result = AutofixResult(
            attemptID: attempt.id,
            head: attempt.head,
            commit: commit,
            addressedThreadIDs: addressed,
        )
    }

    // MARK: Private

    private func summary(fresh: Bool) -> PullRequestSummary {
        PullRequestSummary(
            number: 1,
            title: "Change",
            url: Self.key,
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            headCommit: fresh ? state.freshHead : state.head,
            autofixChecks: AutofixChecks(required: ["test", "build"], results: [
                AutofixCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", runID: "run:1", link: "test"),
                AutofixCheck(
                    name: "build",
                    status: state.checksComplete ? "COMPLETED" : "IN_PROGRESS",
                    conclusion: state.checksComplete ? "FAILURE" : "",
                    runID: "run:1",
                    link: "build",
                ),
                AutofixCheck(
                    name: "optional",
                    status: "IN_PROGRESS",
                    conclusion: "FAILURE",
                    runID: "run:2",
                    link: "optional",
                ),
            ]),
            headRepository: "owner/repo",
        )
    }

    private func threads(fresh: Bool) -> [ReviewThread] {
        if fresh {
            state.freshComments ?? state.comments
        } else {
            state.comments
        }
    }

    private func writers(fresh: Bool) -> Set<String> {
        if fresh {
            state.freshWriters ?? state.writers
        } else {
            state.writers
        }
    }

    private func reviewEvents(fresh: Bool) -> [ReviewComment] {
        if fresh {
            state.freshReviewEvents ?? state.reviewEvents
        } else {
            state.reviewEvents
        }
    }

    private func request(_ bot: ReviewBot) {
        state.requestedBots.append(bot)
    }

    private func target() -> AutofixDriver.Target? {
        guard state.hasSession else {
            return nil
        }

        return AutofixDriver.Target(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            session: AgentSession(
                name: "agent",
                agent: .codexCLI,
                status: .running,
                paneID: "pane",
                activity: state.activity,
            ),
        )
    }

    private func ready(head: String) -> Bool {
        state.localHead == head && [.done, .idle].contains(state.activity) && state.hasSession
    }

    private func deliver(_ attempt: AutofixAttempt, prompt: String) {
        state.deliveries.append(attempt)
        state.prompts.append(prompt)
    }

    private func push(_ commit: String) throws {
        state.pushes.append(commit)
        if state.failPush {
            throw SessionServiceError("Push refused")
        }
    }

    private func resolve(_ id: String) throws {
        state.resolutions.append(id)
        if state.failResolution {
            throw SessionServiceError("Resolution refused")
        }
    }
}
