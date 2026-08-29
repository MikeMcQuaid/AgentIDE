import AgentIDEDomain
import SwiftUI
import TerminalUI

/// One worktree row: branch, session state, commit counts against
/// the default branch and upstream, and pull request state.
struct WorktreeRowView: View {
    // MARK: Internal

    let item: WorktreeItem
    let pullRequest: PullRequestSummary?
    /// Where this branch sits in its stack, how tall the stack is,
    /// and what it is built on.
    let standing: StackStanding

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            leadingIcon
                .padding(.top, Self.iconDrop)
            VStack(alignment: .leading, spacing: 1) {
                titleLine
                detailLine
            }
        }
        // A row never wraps: what does not fit runs under the
        // sidebar's edge and is hidden there.
        .clipped()
    }

    // MARK: Private

    private static let unreadDotSize: CGFloat = 6
    private static let spacing: CGFloat = 4
    private static let badgeSpacing: CGFloat = 2
    /// Sits the icon on the branch line's baseline rather than the
    /// row's very top.
    private static let iconDrop: CGFloat = 2

    /// The agent's monochrome mark, sized to the caption line.
    private static let agentIconSize: CGFloat = 11

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
            return item.session == nil && item.worktree.isHostDirectory == false ? "idle" : ""
        }

        return parts.joined(separator: " ")
    }

    /// What the stack marker says on hover: where this branch is,
    /// what it is built on, and how much rides on it.
    private var stackHelp: String {
        let above = standing.above
        let riding = above == 1 ? "1 pull request builds on it" : "\(above) pull requests build on it"
        return "Stacked: number \(standing.position) of \(standing.height)"
            + (standing.base.map { ", based on " + $0 } ?? "")
            + (above > 0 ? ", and " + riding : "")
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
    /// A directory of your own is named by where it is, since its
    /// branch is not why it is listed.
    private var title: String {
        guard item.worktree.isHostDirectory else {
            return item.worktree.branch
        }

        return item.worktree.path.replacing(
            NSHomeDirectory() + "/",
            with: "~/",
        )
    }

    /// The name of the thing, with the unread dot at the row's
    /// edge, where a column of them reads at a glance rather than
    /// tight against branch names of every length.
    private var titleLine: some View {
        HStack(spacing: Self.spacing) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: Self.spacing)
            if item.hasActionableUnread {
                Circle()
                    .fill(.tint)
                    .frame(width: Self.unreadDotSize, height: Self.unreadDotSize)
                    .hoverHelp("Unseen agent output waiting for you")
            }
        }
    }

    /// What it is doing, under its name. The counts come after what
    /// the pull request is doing: its state is the news, they are
    /// detail.
    @ViewBuilder private var detailLine: some View {
        if item.worktree.isHostDirectory {
            HStack(spacing: Self.spacing) {
                Text(item.worktree.branch)
                    .lineLimit(1)
                Text(counts)
                    .lineLimit(1)
                    .fixedSize()
                    .hoverHelp(countsExplanation)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            worktreeDetailLine
        }
    }

    private var worktreeDetailLine: some View {
        HStack(spacing: Self.spacing) {
            if let agent = item.session?.agent {
                // The brand mark, monochrome so it reads as detail
                // beside the counts rather than shouting colour.
                Image(agent.iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                    .accessibilityLabel(agent.displayName)
                    .hoverHelp("A " + agent.displayName + " session runs here")
            }
            pullRequestBadge
            Text(counts)
                .lineLimit(1)
                .fixedSize()
                .hoverHelp(countsExplanation)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var leadingIcon: some View {
        if item.worktree.isHostDirectory {
            // Sized and coloured as the branch and state icons are,
            // so every row's text starts at the same place.
            Octicon("laptopcomputer", colour: .green)
                .hoverHelp("On your Mac, outside the sandbox")
        } else if let pullRequest {
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
            // The media-player vocabulary, shared with the session
            // strip: play is working, pause is rest, a tick is a
            // turn's answer waiting, a question mark is a question
            // asked of you, stop is an exited process and a dotted
            // circle is herdr unable to tell.
            switch item.session?.status {
            case .running where item.session?.activity == .blocked:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("The agent asked a question or wants an approval")

            case .running where item.session?.activity == .working:
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("The agent is working on its turn")

            case .running where item.session?.activity == .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("The turn is done; the answer is waiting")

            case .running where item.session?.activity == .idle:
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("At rest: nothing asked, or the turn was interrupted")

            case .running:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("Running, but herdr cannot tell what the agent is doing")

            case .finished:
                Image(systemName: "stop.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                    .hoverHelp("The agent's process exited; the conversation stays resumable")

            case nil:
                // The one deliberate difference from a worktree row:
                // the repository's own checkout rests green, home
                // rather than idle.
                Octicon("octicon-git-branch", colour: isMainCheckout ? .green : .secondary)
                    .hoverHelp(isMainCheckout
                        ? "The repository's own checkout, where merged work lands"
                        : "A worktree with no session running")
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
                if standing.isStacked {
                    Octicon("octicon-stack", colour: .secondary)
                        .hoverHelp(stackHelp)
                    Text(String(standing.position) + "/" + String(standing.height))
                        .hoverHelp(stackHelp)
                }
            }
            // Badges keep their width: squeezed, the number and the
            // stack marker broke into a column of digits.
            .lineLimit(1)
            .fixedSize()
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
