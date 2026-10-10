import AgentIDEData

/// Routine waits stay quiet; a person is needed for terminal failures or manual steps.
enum FeedbackNotice {
    case finished
    case attention

    // MARK: Lifecycle

    init?(_ state: PullRequestAutomation) {
        if state.loopStatus == "Finished" {
            self = .finished
        } else if state.loopResult == .failed
            || (state.isLoopRunning && (
                state.pending.hasPrefix("Push the current fixes")
                    || state.pending.hasPrefix("Check out ")
                    || state.pending == "Waiting for a clean worktree before accepting the fix"
                    || state.pending == "Waiting for an agent session on this branch to apply fixes"
                    || state.pending == "Waiting: the original agent session is no longer running"
            ))
        {
            self = .attention
        } else {
            return nil
        }
    }

    // MARK: Internal

    static func change(from previous: PullRequestAutomation?, to state: PullRequestAutomation) -> Self? {
        guard let notice = Self(state), notice != previous.flatMap(Self.init) else {
            return nil
        }

        return notice
    }
}
