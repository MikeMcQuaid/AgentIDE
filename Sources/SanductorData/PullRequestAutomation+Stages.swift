// MARK: - LocalAutofixRounds

/// Local review cycles are independent of continued GitHub observation.
public struct LocalAutofixRounds: Codable, Equatable, Sendable {
    var limit = 1
    var started = 0
    var isComplete = false
}

// MARK: - PullRequestAutomation

public extension PullRequestAutomation {
    /// Existing feedback and local changes precede requests for fresh reviews.
    var isPreparingExistingWork: Bool {
        preparingExistingWork == true
    }

    /// Maximum local review and fix cycles.
    var localRoundLimit: Int {
        get { min(Self.localRoundLimits.upperBound, max(Self.localRoundLimits.lowerBound, localRounds?.limit ?? 1)) }
        set {
            localRounds = localRounds ?? LocalAutofixRounds()
            localRounds?.limit = newValue
        }
    }

    /// Durable count of local fix attempts in this cycle.
    var localRoundsStarted: Int {
        localRounds?.started ?? 0
    }

    /// Local review remains selected until clear or at its cycle limit.
    var isLocalStage: Bool {
        autofixLocalReviews && localRounds?.isComplete != true && localRoundsStarted < localRoundLimit
    }

    /// Starts a new cycle without forgetting previously handled feedback.
    mutating func startLoop() {
        activityLog = []
        collection = nil
        repeatLocalReview = false
        preparingExistingWork = true
        localRounds = LocalAutofixRounds(limit: localRoundLimit)
        isAutomatic = true
        loopResult = nil
        lastResult = ""
        pending = "Starting feedback loop"
    }

    /// Stops further delivery without interrupting the agent's current turn.
    mutating func stopLoop() {
        preparingExistingWork = nil
        activityLog = []
        isAutomatic = false
        attempt = nil
        pending = ""
        loopResult = .stopped
    }

    // MARK: Internal

    internal mutating func countLocalRound(for attempt: AutofixAttempt) {
        guard attempt.commitRequestedHead == nil else {
            return
        }

        if attempt.sources.contains(.localReview) {
            localRounds = localRounds ?? LocalAutofixRounds()
            localRounds?.started += 1
        }
    }

    internal var stageSelection: Self {
        var state = self
        state.autofixLocalReviews = isLocalStage
        return state
    }
}
