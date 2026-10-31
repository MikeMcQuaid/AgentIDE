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
        if isAutomatic != (previous?.isAutomatic ?? false), isAutomatic {
            loopResult = nil
            messages.append("Started " + (isLocalStage ? "local" : "GitHub") + " feedback loop")
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
                AutofixAttempt.Kind.checks: "CI", .reviews: "Human reviews",
                .existingWork: "Existing local work", .conflicts: "Upstream merge conflicts",
                .localReview: "Local AI review", .copilot: "Copilot", .codeRabbit: "CodeRabbit",
                .githubReview: "GitHub quality/security",
            ]
            .filter { attempt.sources.contains($0.key) }
            .map(\.value)
            .sorted()
            .joined(separator: " + ")
            messages.append("Trigger: " + sources + " · head " + String(attempt.head.prefix(Self.headLength)))
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
    /// Remains active while watching feedback or awaiting a fix.
    var isLoopRunning: Bool {
        isAutomatic || attempt != nil
    }

    /// The loop's lifecycle, independent of its current action or wait.
    var loopStatus: String {
        if isLoopRunning {
            "Running"
        } else {
            loopResult?.rawValue ?? (localRoundsStarted > 0 ? "Finished" : "Not started")
        }
    }

    /// Names the stage and round for both waiting and active work.
    var stageSummary: String {
        if isPreparingExistingWork, attempt == nil || attempt?.sources == [.existingWork] {
            return "Existing work"
        }
        guard isLocalStage || attempt?.sources.contains(.localReview) == true else {
            return "GitHub feedback"
        }

        let round = attempt != nil ? max(1, localRoundsStarted) : min(localRoundsStarted + 1, localRoundLimit)
        return "Local round " + String(round) + "/" + String(localRoundLimit)
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
        if isAutomatic == false {
            return "Review gathers local findings. Copy all copies ready feedback. Start loop begins automatic fixes."
        }
        if attempt != nil {
            return "The agent must finish with a matching committed result before gathering more feedback."
        }
        if isPreparingExistingWork {
            return "Wait for selected feedback and finish existing local work."
        }
        if isLocalStage {
            return "Current local findings trigger a fix once this branch’s fixing agent is idle."
        }
        return "New eligible feedback triggers local fixes once the agent is idle"
            + (autofixCI ? " and all CI jobs finish" : "")
            + (autofixReviews || autofixBots ? " and requested reviews finish" : "")
            + ". Push manually when you are ready; autofix only watches GitHub."
    }
}
