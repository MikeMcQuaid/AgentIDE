import Foundation

// MARK: - FeedbackLoopResult

/// The last terminal state, independent of manual reviews and selected sources.
public enum FeedbackLoopResult: String, Codable, Sendable {
    case finished = "Finished"
    case stopped = "Stopped"
    case failed = "Failed"
}

extension PullRequestAutomation {
    private static let headLength = 8

    mutating func recordActivity(comparedTo previous: Self?) {
        guard isLoopRunning || loopResult != nil || pending.isEmpty == false || lastResult.isEmpty == false else {
            return
        }

        var messages = [String]()
        if isAutomatic != (previous?.isAutomatic ?? false) {
            if isAutomatic {
                loopResult = nil
                messages.append("Started " + (isLocalStage ? "local" : "GitHub") + " feedback loop")
            }
        }
        if isLoopRunning == false, loopStatus != (previous?.loopStatus ?? "Not started") {
            messages.append(loopStatus + " feedback loop")
        }
        for (bot, request) in botRequests ?? [:] where request.date != nil && request != previous?.botRequests?[bot] {
            messages.append("Requesting " + bot.displayName + " review")
        }
        if let attempt, attempt.commitRequestedHead == nil,
           attempt.id != previous?.attempt?.id, handledEvents != previous?.handledEvents
        {
            let sources = [
                AutofixAttempt.Kind.checks: "Required CI", .reviews: "Private reviewers",
                .localReview: "Local AI review", .copilot: "Copilot", .codeRabbit: "CodeRabbit",
                .githubReview: "GitHub quality/security",
            ]
            .filter { attempt.sources.contains($0.key) }
            .map(\.value)
            .sorted()
            .joined(separator: " + ")
            messages.append("Trigger: " + sources + " · " + (isLocalStage ? "local" : "GitHub") + " round "
                + String(isLocalStage ? localRoundsStarted : roundsStarted)
                + " · head " + String(attempt.head.prefix(Self.headLength)))
        }
        if pushAutomatically != (previous?.pushAutomatically ?? false) {
            messages.append(pushAutomatically ? "Automatic pushing enabled" : "Automatic pushing disabled")
        }
        if pending.isEmpty == false, pending != previous?.pending {
            messages.append(pending)
        }
        if lastResult.isEmpty == false, lastResult != previous?.lastResult {
            messages.append(lastResult)
        }
        guard messages.isEmpty == false else {
            return
        }

        activityLog = Array(((activityLog ?? []) + messages.map { message in
            FeedbackActivity(
                id: UUID(), date: Date(), message: isLoopRunning ? stageSummary + " · " + message : message,
            )
        }).suffix(100))
    }
}

public extension PullRequestAutomation {
    /// Remains active while a fix or its push confirmation is outstanding.
    var isLoopRunning: Bool {
        isAutomatic || attempt != nil || (pushedCommit != nil && loopResult != .stopped)
    }

    /// The loop's lifecycle, independent of its current action or wait.
    var loopStatus: String {
        if isLoopRunning {
            "Running"
        } else {
            loopResult?.rawValue ?? (roundsStarted > 0 || localRoundsStarted > 0 ? "Finished" : "Not started")
        }
    }

    /// Names the stage and round for both waiting and active work.
    var stageSummary: String {
        let local = isLocalStage || attempt?.sources.contains(.localReview) == true
            || (pushedCommit != nil && roundsStarted == 0 && localRoundsStarted > 0)
        let started = local ? localRoundsStarted : roundsStarted
        let limit = local ? localRoundLimit : roundLimit
        let round = attempt != nil || pushedCommit != nil ? max(1, started) : min(started + 1, limit)
        return (local ? "Local" : "GitHub") + " round " + String(round) + "/" + String(limit)
    }

    /// Combines the lifecycle with the specific activity for compact surfaces.
    var statusSummary: String {
        if activityStatus == loopStatus {
            loopStatus
        } else {
            loopStatus + " · " + activityStatus
        }
    }

    /// The current action or wait, also shown with collapsed settings.
    var activityStatus: String {
        if pending.isEmpty == false {
            return pending
        }
        if collection?.isPending == true {
            return "Gathering local feedback"
        }
        if isAutomatic {
            return "Waiting for the next feedback refresh"
        }
        return loopStatus
    }

    /// What lets the current stage proceed.
    var nextTrigger: String {
        if collection?.isPending == true, isAutomatic == false {
            return "Inspect the review, then Copy all or Start loop."
        }
        if pushedCommit != nil {
            return "GitHub must confirm the pushed commit before gathering more feedback."
        }
        if isAutomatic == false {
            return "Review gathers local findings. Copy all copies ready feedback. Start loop begins automatic fixes."
        }
        if attempt != nil {
            return "The agent must finish with a matching committed result before another round"
                + (localWorktreePath == nil ? " or push." : ".")
        }
        if isLocalStage {
            return "Current local findings trigger a fix once this branch’s fixing agent is idle."
                + (localWorktreePath == nil ? " GitHub work waits." : "")
        }
        return "This branch’s existing agent applies fixes, even with Local AI off, once the pushed head matches"
            + (autofixCI ? ", all required CI jobs finish" : "")
            + (autofixBots ? ", the requested reviewer finishes" : "") + " and the agent is idle."
    }
}
