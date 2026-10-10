@testable import AgentIDEData
import AgentIDEDomain
import AppKit
@testable import PRFeature
import TerminalUI
import Testing

extension PullRequestsModelTests {
    @Test
    func `conversation copies include local findings without enabling autofix`() async {
        let path = "/worktrees/feature"
        let model = makeModel(items: [item(branch: "feature", ahead: 0)], worktreePath: path)
        let selected = summary(7, head: "feature")
        let local = ReviewThread(
            id: "R1",
            path: "file.swift",
            line: 4,
            isResolved: false,
            comments: [ReviewThreadComment(author: "Codex", body: "Local finding")],
            resolveID: "",
        )
        let review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [local])
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 7, url: selected.url)
        state.feedbackWorktreePath = path
        var collection = LocalFeedbackCollection(id: "collection", revision: "r", configuration: "codex")
        collection.review = review
        collection.isPending = false
        state.collection = collection
        model.store.update { value in
            value.localReviews[path] = review
            value.pullRequestAutomation[PullRequestAutomation.key(for: selected.url)] = state
        }
        let remote = ReviewThread(
            id: "github",
            path: "file.swift",
            line: 8,
            isResolved: false,
            comments: [ReviewThreadComment(author: "copilot", body: "Remote finding")],
        )
        model.fetchThreads = { _ in [remote] }
        await model.copyUnresolvedComments(selected)
        #expect(NSPasteboard.general.string(forType: .string) == ReviewThread.digest(of: [remote, local]))
    }

    @Test
    func `local findings stay with their captured branch repository and fork`() {
        let model = makeModel(items: [item(branch: "other", ahead: 0)])
        var review = localReview()
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: summary(7, head: "feature"))?.review == review)
        #expect(model.localReview(for: summary(8, head: "other")) == nil)
        review.repositoryPath = "/different-repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: summary(7, head: "feature")) == nil)
        review.repositoryPath = "/repo"
        review.pullRequestURL = "https://github.com/owner/repo/pull/7"
        review.headRepository = "fork/repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        let fork = PullRequestSummary(
            number: 7,
            title: "",
            url: review.pullRequestURL ?? "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headRepository: "fork/repo",
        )
        #expect(model.localReview(for: fork)?.review == review)
        #expect(model.localReview(for: summary(7, head: "feature")) == nil)
        review.headRepository = "another-fork/repo"
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        #expect(model.localReview(for: fork) == nil)
    }

    @Test
    func `local resolution changes copy counts and cannot change a replacement review`() async {
        let model = makeModel()
        let review = localReview()
        let path = "/worktrees/feature"
        model.store.update { $0.localReviews[path] = review }
        let selected = summary(7, head: "feature")
        #expect(model.reviewCount(for: selected) == 1)
        model.toggleLocalResolved("R1", review: review, path: path)
        #expect(model.reviewCount(for: selected) == 0)
        #expect(model.localReview(for: selected)?.review.threads.first?.codeContext == "captured code")
        await model.copyUnresolvedComments(selected)
        #expect(NSPasteboard.general.string(forType: .string)?.isEmpty == true)
        model.toggleLocalResolved("R1", review: review, path: path)
        #expect(model.reviewCount(for: selected) == 1)
        await model.copyUnresolvedComments(selected)
        #expect(NSPasteboard.general.string(forType: .string) == ReviewThread.digest(of: review.threads))
        let replacement = localReview()
        model.store.update { $0.localReviews[path] = replacement }
        model.toggleLocalResolved("R1", review: review, path: path)
        #expect(model.localReview(for: selected)?.review == replacement)
    }

    @Test
    func `copies read current local decisions after remote comments finish loading`() async {
        let model = makeModel()
        let review = localReview()
        model.store.update { $0.localReviews["/worktrees/feature"] = review }
        model.fetchThreads = { _ in
            #expect(NSPasteboard.general.string(forType: .string) == nil)
            model.toggleLocalResolved("R1", review: review, path: "/worktrees/feature")
            return []
        }
        await model.copyUnresolvedComments(summary(7, head: "feature"))
        #expect(NSPasteboard.general.string(forType: .string)?.isEmpty == true)
    }

    private func localReview() -> LocalReview {
        var review = LocalReview(reviewer: .codexCLI, snapshot: "s", revision: "r", threads: [
            ReviewThread(
                id: "R1",
                path: "file.swift",
                line: 1,
                isResolved: false,
                comments: [ReviewThreadComment(author: "Codex", body: "Local finding")],
                resolveID: "",
                codeContext: "captured code",
            ),
        ])
        review.repositoryPath = "/repo"
        review.branch = "feature"
        return review
    }
}
