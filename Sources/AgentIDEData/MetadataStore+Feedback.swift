public extension MetadataStore {
    /// Resets loop progress at launch while preserving side-effect claims and user preferences.
    func resetFeedbackLoops() {
        update { metadata in
            for key in metadata.pullRequestAutomation.keys {
                guard var state = metadata.pullRequestAutomation[key] else {
                    continue
                }

                state.isAutomatic = false
                state.attempt = nil
                state.localRounds = LocalAutofixRounds(limit: state.localRoundLimit)
                state.roundsStarted = 0
                state.collection = nil
                state.repeatLocalReview = true
                state.pushedCommit = nil
                state.pushedFrom = nil
                state.loopResult = nil
                state.pending = ""
                state.lastResult = ""
                state.activityLog = []
                metadata.pullRequestAutomation[key] = state
            }
        }
    }
}
