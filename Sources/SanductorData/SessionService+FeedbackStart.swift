public extension SessionService {
    /// Starts local fixes and observation without requesting a push or a review.
    func startFeedbackLoop(_ initial: PullRequestAutomation) throws {
        let state = currentFeedback(initial)
        guard state.isLoopRunning == false, state.collection?.isPending != true else {
            return
        }

        try updateFeedback(state) { $0.startLoop() }
    }
}
