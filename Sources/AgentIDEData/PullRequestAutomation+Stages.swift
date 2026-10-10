// MARK: - LocalAutofixRounds

/// Optional in old ledgers; local fixes are pushed only when this stage finishes.
public struct LocalAutofixRounds: Codable, Equatable, Sendable {
    var limit = 1
    var started = 0
    var isComplete = false
    // Older ledgers omit the pause flag.
    // swiftlint:disable:next discouraged_optional_boolean
    var isPaused: Bool?
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

    /// Reaching the local limit requires inspection before a push or remote round.
    var isPausedForReview: Bool {
        localRounds?.isPaused == true
    }

    /// Releases the existing local result without starting another local cycle.
    mutating func continueToGitHub() {
        guard isPausedForReview, isAutomatic == false, attempt == nil, hasRemoteSources else {
            return
        }

        localRounds?.isPaused = false
        localRounds?.isComplete = true
        attempt = localRounds?.lastAttempt
        isAutomatic = true
        pending = "Waiting for this branch's running agent"
    }

    /// Starts a new cycle without forgetting previously handled feedback.
    mutating func startLoop() {
        if isPausedForReview {
            collection = nil
            repeatLocalReview = true
        }
        localRounds = LocalAutofixRounds(limit: localRoundLimit)
        roundsStarted = 0
        isAutomatic = true
        pending = "Waiting for this branch's running agent"
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
