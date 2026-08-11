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
        let image = Image(name)
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

    private let name: String
    private let colour: Color?
}

// MARK: - ChecksStyle

/// The one GitHub status look, using the vendored Octicons: icons
/// and colours per check, review and pull request state, shared by
/// the sidebar rows and the pull request list.
public nonisolated enum ChecksStyle {
    /// The octicon asset for a checks rollup state.
    public static func octiconName(for checks: String) -> String {
        switch checks {
        case "SUCCESS":
            "octicon-check-circle-fill"

        case "FAILURE":
            "octicon-x-circle-fill"

        default:
            "octicon-dot-fill"
        }
    }

    /// The colour for a checks rollup state: GitHub's green, red and
    /// pending yellow.
    public static func colour(for checks: String) -> Color {
        switch checks {
        case "SUCCESS":
            .green

        case "FAILURE":
            .red

        default:
            .yellow
        }
    }

    /// The octicon for an aggregate review decision, nil when there
    /// is none to show.
    public static func reviewOcticonName(for decision: String) -> String? {
        switch decision {
        case "APPROVED":
            "octicon-check"

        case "CHANGES_REQUESTED":
            "octicon-file-diff"

        case "REVIEW_REQUIRED":
            "octicon-eye"

        default:
            nil
        }
    }

    /// The colour for a review decision.
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
    /// is still unknown.
    public static func mergeableOcticonName(for mergeable: String) -> String? {
        switch mergeable {
        case "MERGEABLE":
            "octicon-git-merge"

        case "CONFLICTING":
            "octicon-x-circle-fill"

        default:
            nil
        }
    }

    /// The colour for a mergeability verdict.
    public static func mergeableColour(for mergeable: String) -> Color {
        mergeable == "MERGEABLE" ? .green : .red
    }

    /// A short display name for a GitHub login: the code review bot
    /// shortens to its product name and bot suffixes drop.
    public static func authorDisplayName(_ login: String) -> String {
        if login.lowercased().hasPrefix("copilot") {
            return "Copilot"
        }

        return login.replacing("[bot]", with: "")
    }

    /// The octicon for a pull request's overall state.
    public static func stateOcticonName(state: String, isDraft: Bool) -> String {
        switch state {
        case "MERGED":
            "octicon-git-merge"

        case "CLOSED":
            "octicon-git-pull-request-closed"

        default:
            isDraft ? "octicon-git-pull-request-draft" : "octicon-git-pull-request"
        }
    }

    /// The colour for a pull request's overall state: GitHub's
    /// purple for merged, red for closed, grey for drafts and green
    /// for open.
    public static func stateColour(state: String, isDraft: Bool) -> Color {
        switch state {
        case "MERGED":
            .purple

        case "CLOSED":
            .red

        default:
            isDraft ? .secondary : .green
        }
    }
}
