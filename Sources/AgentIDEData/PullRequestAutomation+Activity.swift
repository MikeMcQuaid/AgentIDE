import Foundation

extension PullRequestAutomation {
    private static let headLength = 8

    mutating func recordActivity(comparedTo previous: Self?) {
        var messages = [String]()
        if isAutomatic != (previous?.isAutomatic ?? false) {
            messages.append(isAutomatic ? "Started " + (isLocalStage ? "local" : "GitHub") + " feedback loop"
                : isPausedForReview ? "Paused for review" : "Stopped feedback loop")
        }
        for (bot, request) in botRequests ?? [:] where request.date != nil && request != previous?.botRequests?[bot] {
            messages.append("Requesting " + bot.displayName + " review")
        }
        if let attempt, attempt.id != previous?.attempt?.id, handledEvents != previous?.handledEvents {
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
            FeedbackActivity(id: UUID(), date: Date(), message: message)
        }).suffix(100))
    }
}

public extension PullRequestAutomation {
    /// The current action or wait, also shown with collapsed settings.
    var activityStatus: String {
        if pending.isEmpty == false {
            return pending
        }
        if collection?.isPending == true {
            return "Gathering local feedback"
        }
        if isPausedForReview {
            return "Paused for you to inspect the local fixes"
        }
        if isAutomatic {
            return "Waiting for the next feedback refresh"
        }
        return "Off"
    }

    /// What lets the current stage proceed.
    var nextTrigger: String {
        if isPausedForReview {
            return "Inspect changes, then Continue to GitHub or Start loop for another local cycle."
        }
        if collection?.isPending == true, isAutomatic == false {
            return "Inspect the review, then Copy all or Start loop."
        }
        if isAutomatic == false {
            return "Review gathers local findings. Copy all copies ready feedback. Start loop begins automatic fixes."
        }
        if pushedCommit != nil {
            return "GitHub must confirm the pushed commit before gathering more feedback."
        }
        if attempt != nil {
            return "The agent must finish with a matching committed result before another round or push."
        }
        if isLocalStage {
            return "Current local findings trigger a fix once this branch’s running agent is idle. GitHub work waits."
        }
        return "New selected feedback triggers one combined fix once the pushed head matches"
            + (autofixCI ? ", all required CI jobs finish" : "")
            + (autofixBots ? ", the requested reviewer finishes" : "") + " and the agent is idle."
    }
}
