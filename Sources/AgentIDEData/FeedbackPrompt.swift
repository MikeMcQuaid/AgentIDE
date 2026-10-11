import Foundation

/// Editable briefs; captured scope and the result protocol are appended by the caller.
public enum FeedbackPrompt: String, CaseIterable, Sendable {
    case localReview = "Local review"
    case localFix = "Local fix and commit"
    case remoteFix = "GitHub fix and commit"
    case commit = "Commit unfinished fixes"

    // MARK: Public

    public var key: String {
        "feedbackPrompt." + rawValue
    }

    public var defaultText: String {
        switch self {
        case .localReview:
            LocalReviewInput.instructions

        case .localFix:
            "Verify the local review findings, make focused fixes, run relevant checks and commit the changes."

        case .remoteFix:
            "Verify all supplied reviews and failing required CI output, make focused fixes, "
                + "run relevant local checks and commit the changes."

        case .commit:
            "Inspect the uncommitted changes and commit only the fixes you made for the original autofix task. "
                + "Run relevant checks before committing. Do not start another review or fix round."
        }
    }

    public func text(defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: key),
              stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return defaultText
        }

        return stored
    }
}
