import AgentIDEDomain
import Foundation

extension SessionService {
    func collectLocalFeedback(
        _ state: PullRequestAutomation,
        worktree: Worktree,
        wait: Bool,
    ) async throws -> LocalFeedbackCollection? {
        guard state.hasLocalSources else {
            return nil
        }

        let path = worktree.path
        let key = PullRequestAutomation.key(for: state.url)
        let revision = try await localReviewRevision(worktreePath: path)
        let configuration = (state.reviewer ?? localReviewer(worktreePath: path)).rawValue
        if let collected = store.load().pullRequestAutomation[key]?.collection,
           collected.revision == revision, collected.configuration == configuration
        {
            if collected.isPending {
                guard await feedbackCollector.isRunning(key) else {
                    try await recoverFeedback(currentFeedback(state))
                    throw SessionServiceError("Review interrupted. Choose Review to retry.")
                }

                if wait {
                    await feedbackCollector.wait(key)
                }
                return store.load().pullRequestAutomation[key]?.collection
            }
            return collected
        }
        guard await feedbackCollector.isRunning(key) == false else {
            return nil
        }

        let collection = LocalFeedbackCollection(
            id: UUID().uuidString, revision: revision, configuration: configuration,
        )
        try store.updatePersisting { value in
            value.pullRequestAutomation[key]?.feedbackWorktreePath = path
            value.pullRequestAutomation[key]?.collection = collection
            value.pullRequestAutomation[key]?.pending = "Gathering local feedback"
        }
        await feedbackCollector.start(key) {
            await runFeedbackCollection(collection, state: state, worktree: worktree)
        }
        if wait {
            await feedbackCollector.wait(key)
        }
        return store.load().pullRequestAutomation[key]?.collection
    }

    func runFeedbackCollection(
        _ original: LocalFeedbackCollection,
        state: PullRequestAutomation,
        worktree: Worktree,
    ) async {
        var collection = original
        do {
            try requireSandboxWorkspace(worktree.path)
            guard await git.currentBranch(worktreePath: worktree.path) == worktree.branch else {
                throw SessionServiceError("The checked-out branch changed before gathering feedback.")
            }

            store.update { value in
                value.pullRequestAutomation[PullRequestAutomation.key(for: state.url)]?.pending =
                    "Reviewing local changes"
            }
            collection.review = try await reviewFeedback(state, worktree: worktree, revision: collection.revision)
            collection.failure = collection.review?.failure
            guard try await localReviewRevision(worktreePath: worktree.path) == collection.revision else {
                throw SessionServiceError("The code changed while gathering feedback. Gather it again.")
            }
        } catch {
            collection.failure = error.localizedDescription
        }
        collection.isPending = false
        let finished = collection
        store.update { value in
            let key = PullRequestAutomation.key(for: state.url)
            guard value.pullRequestAutomation[key]?.collection?.id == finished.id else {
                return
            }

            value.pullRequestAutomation[key]?.collection = finished
            value.pullRequestAutomation[key]?.repeatLocalReview = false
            value.pullRequestAutomation[key]?.pending = ""
            value.pullRequestAutomation[key]?.lastResult = finished.failure
                ?? (finished.review?.remaining ?? 0 > 0 ? "Local findings are ready" : "No local findings")
            if let review = finished.review {
                value.localReviews[worktree.path] = review
            }
        }
    }

    func reviewFeedback(
        _ state: PullRequestAutomation, worktree: Worktree, revision: String,
    ) async throws -> LocalReview? {
        let reviewer = state.reviewer ?? localReviewer(worktreePath: worktree.path)
        if state.repeatLocalReview == false, let saved = store.load().localReviews[worktree.path],
           saved.revision == revision,
           saved.reviewer == reviewer, saved.failure == nil
        {
            return saved
        }
        let base = await reviewBase(for: worktree) ?? "HEAD"
        let ancestor = await git.mergeBase(base, "HEAD", worktreePath: worktree.path) ?? "HEAD"
        let files = try await DiffParser.parse(git.uncommittedDiff(worktreePath: worktree.path, comparedTo: ancestor))
        guard files.isEmpty == false else {
            return nil
        }

        return try await runLocalReview(
            files: files,
            worktreePath: worktree.path,
            reviewer: reviewer,
            instructions: store.load().localReviews[worktree.path]?.instructions ?? LocalReviewInput.instructions,
        )
    }
}
