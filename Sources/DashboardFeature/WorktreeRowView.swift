import AgentIDEDomain
import SwiftUI
import TerminalUI

/// One worktree row: branch, session state, commit counts against
/// the default branch and upstream, and pull request state.
struct WorktreeRowView: View {
    // MARK: Internal

    let item: WorktreeItem
    let pullRequest: PullRequestSummary?
    let stackDepth: Int

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            leadingIcon
                .padding(.top, Self.iconDrop)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Self.spacing) {
                    Text(item.worktree.branch).lineLimit(1)
                    if item.hasUnread {
                        Circle()
                            .fill(.tint)
                            .frame(width: Self.unreadDotSize, height: Self.unreadDotSize)
                            .hoverHelp("Unseen agent output")
                    }
                }
                HStack(spacing: Self.spacing) {
                    Text(badges)
                        .hoverHelp(badgesExplanation)
                    pullRequestBadge
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Private

    private static let unreadDotSize: CGFloat = 6
    private static let spacing: CGFloat = 4
    private static let badgeSpacing: CGFloat = 2
    private static let iconStackSpacing: CGFloat = 1

    /// Sits the icon on the branch line's baseline rather than the
    /// row's very top.
    private static let iconDrop: CGFloat = 2

    private var badges: String {
        var parts = [String]()
        if let agent = item.session?.agent {
            parts.append(agent.displayName)
        }
        if let ahead = item.aheadOfDefault, ahead > 0 {
            parts.append("↑\(ahead)")
        }
        if let behind = item.behindDefault, behind > 0 {
            parts.append("↓\(behind)")
        }
        if let unpushed = item.aheadOfUpstream, unpushed > 0 {
            parts.append("⇡\(unpushed)")
        }
        if item.isDirty {
            parts.append("±")
        }
        return parts.isEmpty ? "idle" : parts.joined(separator: " ")
    }

    private var badgesExplanation: String {
        """
        ↑ commits ahead of the default branch, ↓ behind it, \
        ⇡ committed but not pushed, ± uncommitted changes
        """
    }

    /// A worktree with a pull request leads with its state icon over
    /// a clickable CI dot; otherwise the session symbol or branch
    /// octicon shows.
    @ViewBuilder private var leadingIcon: some View {
        if let pullRequest {
            VStack(spacing: Self.iconStackSpacing) {
                Octicon(
                    pullRequest.hasAutomerge
                        ? "octicon-git-merge-queue"
                        : ChecksStyle.stateOcticonName(state: pullRequest.state, isDraft: pullRequest.isDraft),
                    colour: pullRequest.hasAutomerge
                        ? .blue
                        : ChecksStyle.stateColour(state: pullRequest.state, isDraft: pullRequest.isDraft),
                )
                .hoverHelp(stateHelp(for: pullRequest))
                checksDot(for: pullRequest)
            }
        } else {
            switch item.session?.status {
            case .running:
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityHidden(true)

            case .finished:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)

            case nil:
                Octicon("octicon-git-branch", colour: .secondary)
            }
        }
    }

    @ViewBuilder private var pullRequestBadge: some View {
        if let pullRequest {
            HStack(spacing: Self.badgeSpacing) {
                Button {
                    LinkOpener.open(pullRequest.url)
                } label: {
                    Text("#" + String(pullRequest.number))
                }
                .buttonStyle(.plain)
                .hoverHelp("Open pull request #" + String(pullRequest.number)
                    + " in the Browser tab; Cmd-click for the system browser")
                if let review = ChecksStyle.reviewOcticonName(for: pullRequest.reviewDecision) {
                    Octicon(review, colour: ChecksStyle.reviewColour(for: pullRequest.reviewDecision))
                        .hoverHelp("Review: " + pullRequest.reviewDecision.lowercased())
                }
                if stackDepth > 1 {
                    Octicon("octicon-stack", colour: .secondary)
                        .hoverHelp("Stacked: \(stackDepth) pull requests based on each other")
                    Text(String(stackDepth))
                }
            }
        }
    }

    private func checksDot(for pullRequest: PullRequestSummary) -> some View {
        Button {
            LinkOpener.open(pullRequest.checksClickURL)
        } label: {
            Octicon("octicon-dot-fill", colour: ChecksStyle.colour(for: pullRequest.checks))
                .accessibilityLabel("Checks: \(pullRequest.checks.lowercased())")
        }
        .buttonStyle(.plain)
        .hoverHelp(
            pullRequest.failingCheckLinks.count == 1
                ? "CI \(pullRequest.checks.lowercased()): open the one failing run; Cmd-click for the system browser"
                : "CI \(pullRequest.checks.lowercased()): open the checks page; Cmd-click for the system browser",
        )
    }

    private func stateHelp(for pullRequest: PullRequestSummary) -> String {
        if pullRequest.hasAutomerge {
            "Automerge enabled"
        } else if pullRequest.isDraft {
            "Draft pull request"
        } else {
            pullRequest.state == "OPEN" ? "Open pull request" : pullRequest.state.capitalized + " pull request"
        }
    }
}
