// MARK: - LocalAutofixRounds

/// Optional in old ledgers; local fixes are pushed only when this stage finishes.
public struct LocalAutofixRounds: Codable, Equatable, Sendable {
    var limit = 1
    var started = 0
    var isComplete = false
    var lastAttempt: AutofixAttempt?
    var commit: String?
}

// MARK: - PullRequestAutomation

public extension PullRequestAutomation {
    /// Maximum local fix rounds before moving on to GitHub feedback.
    var localRoundLimit: Int {
        get { localRounds?.limit ?? 1 }
        set {
            localRounds = localRounds ?? LocalAutofixRounds()
            localRounds?.limit = newValue
        }
    }

    /// Durable count of local fix attempts in this cycle.
    var localRoundsStarted: Int {
        localRounds?.started ?? 0
    }

    /// Remote CI and reviews are deferred until this stage ends.
    var isLocalStage: Bool {
        autofixLocalReviews && localRounds?.isComplete != true
    }

    /// Starts a new cycle without forgetting previously handled feedback.
    mutating func startLoop() {
        activityLog = []
        collection = nil
        repeatLocalReview = true
        localRounds = LocalAutofixRounds(limit: localRoundLimit)
        roundsStarted = 0
        isAutomatic = true
        loopResult = nil
        lastResult = ""
        pending = "Starting feedback loop"
    }

    /// Stops further delivery without interrupting the agent's current turn.
    mutating func stopLoop() {
        activityLog = []
        isAutomatic = false
        attempt = nil
        pending = ""
        loopResult = .stopped
    }

    // MARK: Internal

    internal var stageSelection: Self {
        var state = self
        if isLocalStage {
            state.autofixCI = false
            state.autofixReviews = false
            state.autofixBots = false
        } else {
            state.autofixLocalReviews = false
        }
        return state
    }
}
