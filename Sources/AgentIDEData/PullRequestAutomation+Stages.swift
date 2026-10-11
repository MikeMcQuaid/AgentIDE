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
    /// Existing feedback and local changes precede requests for fresh reviews.
    var isPreparingExistingWork: Bool {
        preparingExistingWork == true
    }

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
        failedPush = nil
        activityLog = []
        collection = nil
        repeatLocalReview = false
        preparingExistingWork = true
        localRounds = LocalAutofixRounds(limit: localRoundLimit)
        roundsStarted = 0
        isAutomatic = true
        loopResult = nil
        lastResult = ""
        pending = "Starting feedback loop"
    }

    /// Stops further delivery without interrupting the agent's current turn.
    mutating func stopLoop() {
        preparingExistingWork = nil
        failedPush = nil
        activityLog = []
        isAutomatic = false
        attempt = nil
        pending = ""
        loopResult = .stopped
    }

    // MARK: Internal

    internal mutating func countRound(for attempt: AutofixAttempt) {
        guard attempt.commitRequestedHead == nil else {
            return
        }

        if attempt.sources.contains(.localReview) {
            localRounds = localRounds ?? LocalAutofixRounds()
            localRounds?.started += 1
        }
        if attempt.sources.subtracting([.localReview, .existingWork]).isEmpty == false {
            roundsStarted += 1
        }
    }

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
