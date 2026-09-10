import AgentIDEDomain

/// Asking Copilot for a review from the conversation's header.
/// Split from the actions for length.
extension PullRequestsModel {
    /// Whether Copilot can be asked now: the pull request is open,
    /// GitHub shows no request still waiting on it, and no ask made
    /// from here is still unanswered, which is an ask with no Copilot
    /// review newer than it. The ask's time lives in the metadata,
    /// so a relaunch changes nothing, and a review the reader did not
    /// carry (the poll's listing reads none) keeps the ask standing
    /// until the pane's own read sees one.
    func canRequestCopilotReview(_ summary: PullRequestSummary) -> Bool {
        // Read so a recorded ask repaints whoever asked.
        _ = copilotAsks
        guard summary.state == "OPEN", summary.awaitsCopilotReview == false else {
            return false
        }
        guard let asked = pullRequests.copilotAskedAt(repositoryPath: repository.path, number: summary.number) else {
            return true
        }

        return summary.copilotReviewedAt.map { $0 > asked } ?? false
    }

    /// Asks Copilot to review the pull request, or to review it
    /// again after a push, remembers when, then reads the summary
    /// back.
    func requestCopilotReview(_ summary: PullRequestSummary) async -> Bool {
        let asked = await act { try await performCopilotRequest(summary.number) }
        if asked {
            pullRequests.rememberCopilotAsk(repositoryPath: repository.path, number: summary.number)
            copilotAsks += 1
            note("Asked Copilot to review #" + String(summary.number) + ".")
        }
        await refreshSummary(summary.number)
        return asked
    }
}
