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
                    // The dot sits at the row's edge, where a column
                    // of them reads at a glance, rather than tight
                    // against branch names of every length.
                    Spacer(minLength: Self.spacing)
                    if item.hasUnread {
                        Circle()
                            .fill(.tint)
                            .frame(width: Self.unreadDotSize, height: Self.unreadDotSize)
                            .hoverHelp("Unseen agent output")
                    }
                }
                HStack(spacing: Self.spacing) {
                    if let agent = item.session?.agent {
                        Text(agent.displayName)
                    }
                    pullRequestBadge
                    // The counts come after what the pull request is
                    // doing: its state is the news, they are detail.
                    Text(counts)
                        .hoverHelp(countsExplanation)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Private

    private static let unreadDotSize: CGFloat = 6
    private static let spacing: CGFloat = 4
    private static let badgeSpacing: CGFloat = 2
    /// Sits the icon on the branch line's baseline rather than the
    /// row's very top.
    private static let iconDrop: CGFloat = 2

    private var counts: String {
        var parts = [String]()
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
        // Something has to say the row is not just quiet but idle,
        // and only when nothing else on the line does.
        if parts.isEmpty {
            return item.session == nil ? "idle" : ""
        }

        return parts.joined(separator: " ")
    }

    private var countsExplanation: String {
        """
        ↑ commits ahead of the default branch, ↓ behind it, \
        ⇡ committed but not pushed, ± uncommitted changes
        """
    }

    /// Whether the row is a repository's own checkout rather than a
    /// worktree, which is where its default branch lives.
    private var isMainCheckout: Bool {
        item.worktree.path == item.worktree.repositoryPath
    }

    /// A worktree with a pull request leads with its state; anything
    /// else leads with what is running, or with the branch itself,
    /// green on a repository's own checkout since that branch is
    /// where merged work lands rather than something to open.
    @ViewBuilder private var leadingIcon: some View {
        if let pullRequest {
            Octicon(
                ChecksStyle.stateOcticonName(
                    state: pullRequest.state,
                    isDraft: pullRequest.isDraft,
                    isQueued: pullRequest.isQueued,
                ),
                colour: ChecksStyle.stateColour(
                    state: pullRequest.state,
                    isDraft: pullRequest.isDraft,
                    isQueued: pullRequest.isQueued,
                ),
            )
            .hoverHelp(stateHelp(for: pullRequest))
        } else {
            switch item.session?.status {
            case .running where item.session?.activity == .blocked:
                // The one state that needs the user: herdr saw an
                // approval or question waiting.
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("The agent is waiting on your input")

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
                Octicon("octicon-git-branch", colour: isMainCheckout ? .green : .secondary)
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
                // CI, reviews and conversations are what a pull
                // request still needs; once it is merged or closed
                // they are history, and the state icon says it all.
                if pullRequest.state == "OPEN" {
                    checksDot(for: pullRequest)
                }
                if let review = reviewIcon(for: pullRequest) {
                    Octicon(review, colour: ChecksStyle.reviewColour(for: pullRequest.reviewDecision))
                        .hoverHelp("Review: " + pullRequest.reviewDecision.lowercased())
                }
                if pullRequest.state == "OPEN", pullRequest.unresolvedComments > 0 {
                    Octicon(ChecksStyle.commentOcticonName, colour: .secondary)
                        .hoverHelp("\(pullRequest.unresolvedComments) unresolved review conversations")
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

    /// The review badge, absent once the pull request is merged or
    /// closed: its verdict stopped being something to act on.
    private func reviewIcon(for pullRequest: PullRequestSummary) -> String? {
        pullRequest.state == "OPEN" ? ChecksStyle.reviewOcticonName(for: pullRequest.reviewDecision) : nil
    }

    private func stateHelp(for pullRequest: PullRequestSummary) -> String {
        if pullRequest.isQueued {
            "In the merge queue"
        } else if pullRequest.hasAutomerge {
            "Set to merge automatically"
        } else if pullRequest.isDraft {
            "Draft pull request"
        } else {
            pullRequest.state == "OPEN" ? "Open pull request" : pullRequest.state.capitalized + " pull request"
        }
    }
}
