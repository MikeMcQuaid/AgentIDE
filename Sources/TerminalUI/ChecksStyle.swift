import SwiftUI

// MARK: - Octicon

/// One vendored Octicon at a consistent small size, tinted by the
/// given colour or inheriting the context's.
public struct Octicon: View {
    // MARK: Lifecycle

    /// Creates the icon from an asset name.
    public init(_ name: String, colour: Color? = nil) {
        self.name = name
        self.colour = colour
    }

    // MARK: Public

    /// The scaled template image. Decorative by default; interactive
    /// owners label their surrounding control.
    public var body: some View {
        // GitHub has no octicon for everything the app shows; a name
        // without the vendored prefix is an SF Symbol.
        let image = (name.hasPrefix(Self.octiconPrefix) ? Image(name) : Image(systemName: name))
            .resizable()
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)
        if let colour {
            image.foregroundStyle(colour)
        } else {
            image
        }
    }

    // MARK: Private

    private static let size: CGFloat = 12
    private static let octiconPrefix = "octicon-"

    private let name: String
    private let colour: Color?
}

// MARK: - ChecksStyle

/// The one GitHub status look, using the vendored Octicons: icons
/// and colours per check, review and pull request state, shared by
/// the sidebar rows and the pull request list.
public nonisolated enum ChecksStyle {
    /// The badge for unresolved review conversations, which are
    /// something to answer rather than a verdict on the branch.
    public static let commentOcticonName = "octicon-comment"

    /// The badge for a checks rollup, in the sidebar and the pull
    /// request row alike: a dot whatever the checks say, so the
    /// colour is the whole of the state and one run's progress
    /// never changes the shape of the row. The tick belongs to a
    /// review's approval and the diff to a review's changes; a
    /// glyph shared between two facts says neither.
    public static let checksOcticonName = "octicon-dot-fill"

    /// The colour for a checks rollup state: green, red, and orange
    /// while they run, which reads against a sidebar's background
    /// where yellow did not.
    public static func colour(for checks: String) -> Color {
        switch checks {
        case "SUCCESS":
            .green

        case "FAILURE":
            .red

        default:
            .orange
        }
    }

    /// The octicon for an aggregate review decision, nil when there
    /// is none to show. A review that is required but has not
    /// happened is waiting rather than failing, so it gets a clock
    /// rather than a verdict. Changes requested is GitHub's own
    /// glyph for it, a diff, which says a person has written on the
    /// code: the crossed circle it used to share said "failed" in
    /// the same breath as the checks beside it.
    public static func reviewOcticonName(for decision: String) -> String? {
        switch decision {
        case "APPROVED":
            "octicon-check-circle-fill"

        case "CHANGES_REQUESTED":
            "octicon-file-diff"

        case "REVIEW_REQUIRED":
            "clock"

        default:
            nil
        }
    }

    /// What a review badge means, in words: the glyph says which of
    /// the three red badges a row can carry this one is, and the
    /// help says what to do about it.
    public static func reviewHelp(for decision: String) -> String {
        switch decision {
        case "APPROVED":
            "Approved by a reviewer"

        case "CHANGES_REQUESTED":
            "A reviewer asked for changes"

        case "REVIEW_REQUIRED":
            "Waiting on a required review"

        default:
            "Review: " + decision.lowercased()
        }
    }

    /// What a mergeability badge means, in words.
    public static func mergeableHelp(for mergeable: String) -> String {
        if mergeable == "MERGEABLE" {
            "No conflicts with the base branch"
        } else {
            "Conflicts with the base branch; rebase to resolve them"
        }
    }

    /// The colour for a review decision: a verdict is green or red,
    /// and waiting is neither.
    public static func reviewColour(for decision: String) -> Color {
        switch decision {
        case "APPROVED":
            .green

        case "CHANGES_REQUESTED":
            .red

        default:
            .secondary
        }
    }

    /// The octicon for GitHub's mergeability verdict, nil while it
    /// is still unknown. A conflict warns rather than fails: it is
    /// nobody's verdict on the work, it is the one state a pull
    /// request cannot leave on its own, and its triangle is legible
    /// at twelve points beside the circles either side of it.
    public static func mergeableOcticonName(for mergeable: String) -> String? {
        switch mergeable {
        case "MERGEABLE":
            "octicon-git-merge"

        case "CONFLICTING":
            "exclamationmark.triangle.fill"

        default:
            nil
        }
    }

    /// The colour for a mergeability verdict.
    public static func mergeableColour(for mergeable: String) -> Color {
        if mergeable == "MERGEABLE" {
            .green
        } else {
            .red
        }
    }

    /// A short display name for a GitHub login: the code review bot
    /// shortens to its product name and bot suffixes drop.
    public static func authorDisplayName(_ login: String) -> String {
        if login.lowercased().hasPrefix("copilot") {
            return "Copilot"
        }

        return login.replacing("[bot]", with: "")
    }

    /// The octicon for a pull request's overall state. A queued one
    /// says so first: what happens next is the queue, whatever the
    /// pull request itself looks like.
    public static func stateOcticonName(state: String, isDraft: Bool, isQueued: Bool = false) -> String {
        if isQueued {
            return "octicon-git-merge-queue"
        }

        switch state {
        case "MERGED":
            return "octicon-git-merge"

        case "CLOSED":
            return "octicon-git-pull-request-closed"

        default:
            return isDraft ? "octicon-git-pull-request-draft" : "octicon-git-pull-request"
        }
    }

    /// The colour for a pull request's overall state: GitHub's
    /// purple once merged, green while open, orange in the queue,
    /// red closed and grey for a draft nobody is asked to look at
    /// yet. Orange rather than yellow, which a sidebar's own
    /// background leaves almost invisible.
    public static func stateColour(state: String, isDraft: Bool, isQueued: Bool = false) -> Color {
        if isQueued {
            return .orange
        }

        switch state {
        case "MERGED":
            return .purple

        case "CLOSED":
            return .red

        default:
            return isDraft ? .secondary : .green
        }
    }
}
