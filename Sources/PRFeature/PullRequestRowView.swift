import AgentIDEDomain
import SwiftUI
import TerminalUI

/// One pull request's header: state, checks, review and mergeability
/// icons around the title over the branch and author, with the merge
/// and fix actions when shown. The list rows share this look with
/// the conversation view's header.
struct PullRequestRowView: View {
    // MARK: Internal

    static let rowPadding: CGFloat = 4

    let summary: PullRequestSummary
    let stackDepth: Int
    let showsActions: Bool
    let onCopyComments: @MainActor () async -> Void
    let onOpenChecks: @MainActor () async -> Void

    /// Opens the title and body for editing; nil where the row is
    /// not the open conversation's header, or the pull request is
    /// no longer open to edit.
    var onEdit: (@MainActor () -> Void)?

    /// Asks Copilot for a review, or another after a push; nil where
    /// the row is not the open conversation's header.
    var onAskCopilot: (@MainActor () async -> Bool)?

    /// Whether Copilot can be asked now, which the model decides
    /// from GitHub's pending request and its own record of the last
    /// ask.
    var canAskCopilot = true

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                titleRow
                caption
            }
            Spacer()
            if showsActions {
                actions
            }
        }
        .padding(.vertical, Self.rowPadding)
        // The same actions as the buttons, reachable from list rows
        // that hide them.
        .contextMenu {
            Button("Copy Unresolved Comments") { Task { await onCopyComments() } }
            Button("Open Failing Checks") { Task { await onOpenChecks() } }
            Divider()
            Button("Open in Browser") { LinkOpener.open(summary.url) }
        }
    }

    // MARK: Private

    /// Whether the ask is on its way to GitHub.
    @State private var isAskingCopilot = false

    private var stateHelp: String {
        if summary.state != "OPEN" {
            summary.state.capitalized + " pull request"
        } else if summary.isDraft {
            "Draft pull request"
        } else {
            "Open pull request"
        }
    }

    private var caption: some View {
        HStack(spacing: Self.rowPadding) {
            Text(summary.headBranch)
                .font(NameStyle.font)
                .lineLimit(1)
                .truncationMode(.middle)
            let author = ChecksStyle.authorDisplayName(summary.author ?? "")
            if author.isEmpty == false {
                Text("· " + author).font(.callout).lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var titleRow: some View {
        HStack(spacing: Self.rowPadding) {
            Octicon(
                ChecksStyle.stateOcticonName(state: summary.state, isDraft: summary.isDraft),
                colour: ChecksStyle.stateColour(state: summary.state, isDraft: summary.isDraft),
            )
            .hoverHelp(stateHelp)
            Button {
                LinkOpener.open(summary.url)
            } label: {
                Text("#" + String(summary.number)).font(.headline)
            }
            .buttonStyle(.plain)
            .hoverHelp("Open the pull request in the Browser tab; Cmd-click for the Cmd-click browser set in Settings")
            // Light listings skip the status fields, so an unknown
            // check state shows nothing rather than pending.
            if summary.checks.isEmpty == false {
                checksButton
            }
            statusBadges
            Text(summary.title).font(.headline).lineLimit(1)
        }
    }

    @ViewBuilder private var statusBadges: some View {
        if let review = ChecksStyle.reviewOcticonName(for: summary.reviewDecision) {
            Octicon(review, colour: ChecksStyle.reviewColour(for: summary.reviewDecision))
                .hoverHelp(ChecksStyle.reviewHelp(for: summary.reviewDecision))
        }
        if summary.state == "OPEN", let mergeable = ChecksStyle.mergeableOcticonName(for: summary.mergeable) {
            Octicon(mergeable, colour: ChecksStyle.mergeableColour(for: summary.mergeable))
                .hoverHelp(ChecksStyle.mergeableHelp(for: summary.mergeable))
        }
        if summary.hasAutomerge {
            Octicon("octicon-git-merge-queue", colour: .blue)
                .hoverHelp("Automerge enabled")
        }
        if stackDepth > 1 {
            Octicon("octicon-stack", colour: .secondary)
                .hoverHelp("Stacked: \(stackDepth) pull requests based on each other")
            Text(String(stackDepth)).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The same jump the sidebar's icon makes: the one failing run
    /// when there is exactly one, the checks page otherwise.
    private var checksButton: some View {
        Button {
            LinkOpener.open(summary.checksClickURL)
        } label: {
            Octicon(
                ChecksStyle.checksOcticonName,
                colour: ChecksStyle.colour(for: summary.checks),
            )
            .accessibilityLabel("Checks: \(summary.checks.lowercased())")
        }
        .buttonStyle(.plain)
        .hoverHelp(
            summary.failingCheckLinks.count == 1
                ? "Open the one failing run in the Browser tab; Cmd-click for the system browser"
                : "Open the checks page in the Browser tab; Cmd-click for the system browser",
        )
    }

    /// Asks Copilot for a review. While a request is still waiting
    /// on Copilot, asking again would only queue the same review, so
    /// the icon dims until it answers.
    @ViewBuilder private var copilotButton: some View {
        if let onAskCopilot, summary.state == "OPEN" {
            Button {
                isAskingCopilot = true
                Task {
                    _ = await onAskCopilot()
                    isAskingCopilot = false
                }
            } label: {
                // Dimmed in its own colour as well as by the button,
                // so a request still waiting reads at a glance.
                Octicon("octicon-copilot", colour: canAskCopilot && isAskingCopilot == false ? .primary : .secondary)
                    .accessibilityLabel("Ask Copilot to review")
            }
            .buttonStyle(.glass)
            .disabled(canAskCopilot == false || isAskingCopilot)
            .hoverHelp(
                canAskCopilot
                    ? "Ask Copilot to review this pull request, or to review it again after a push"
                    : "Copilot has been asked to review this pull request and has not answered yet",
            )
        }
    }

    private var actions: some View {
        HStack(spacing: Self.rowPadding) {
            if let onEdit, summary.state == "OPEN" {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .accessibilityLabel("Edit title and body")
                }
                .buttonStyle(.glass)
                .hoverHelp("Edit the title and body, to say what was actually pushed before it merges")
            }
            copilotButton
            Button {
                LinkOpener.open(summary.url)
            } label: {
                Image(systemName: "safari")
                    .accessibilityLabel("Open pull request in browser")
            }
            .buttonStyle(.glass)
            .hoverHelp("Open this pull request in the Browser tab; Cmd-click for the Cmd-click browser set in Settings")
        }
    }
}
