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
    let hasMergeQueue: Bool
    let showsActions: Bool
    let onAutomerge: @MainActor () async -> Void
    let onMerge: @MainActor () async -> Void
    let onCopyComments: @MainActor () async -> Void
    let onCopyChecks: @MainActor () async -> Void
    let onResolveAll: @MainActor () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                titleRow
                Text(caption).font(.callout).foregroundStyle(.secondary)
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
            Button("Copy Failing Checks") { Task { await onCopyChecks() } }
            Button("Resolve All Conversations") { Task { await onResolveAll() } }
            Divider()
            Button("Open in Browser") { LinkOpener.open(summary.url) }
        }
    }

    // MARK: Private

    private var caption: String {
        let author = ChecksStyle.authorDisplayName(summary.author ?? "")
        return author.isEmpty ? summary.headBranch : summary.headBranch + " · " + author
    }

    private var stateHelp: String {
        if summary.state != "OPEN" {
            summary.state.capitalized + " pull request"
        } else if summary.isDraft {
            "Draft pull request"
        } else {
            "Open pull request"
        }
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
            .hoverHelp("Open the pull request in the Browser tab; Cmd-click for the system browser")
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
                .hoverHelp("Review: " + summary.reviewDecision.lowercased())
        }
        if summary.state == "OPEN", let mergeable = ChecksStyle.mergeableOcticonName(for: summary.mergeable) {
            Octicon(mergeable, colour: ChecksStyle.mergeableColour(for: summary.mergeable))
                .hoverHelp(
                    summary.mergeable == "MERGEABLE"
                        ? "No conflicts with the base branch"
                        : "Conflicts with the base branch",
                )
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
                ChecksStyle.octiconName(for: summary.checks),
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

    @ViewBuilder private var actions: some View {
        BusyButton("", busy: "", systemImage: "text.bubble", action: onCopyComments)
            .hoverHelp("Copy every unresolved review conversation to the clipboard")
        BusyButton("", busy: "", systemImage: "exclamationmark.triangle", action: onCopyChecks)
            .hoverHelp("Copy the failing checks to the clipboard")
        BusyButton("", busy: "", systemImage: "checkmark.bubble", action: onResolveAll)
            .hoverHelp("Mark every unresolved conversation resolved")
        Button {
            LinkOpener.open(summary.url)
        } label: {
            Image(systemName: "safari")
                .accessibilityLabel("Open pull request in browser")
        }
        .buttonStyle(.glass)
        .hoverHelp("Open this pull request in the Browser tab; Cmd-click for the system browser")
        // One merge action, matching what the pull request can do
        // right now: merge when green and mergeable, automerge
        // while checks are still running.
        if summary.state == "OPEN" {
            if summary.checks == "SUCCESS", summary.mergeable == "MERGEABLE" {
                BusyButton(
                    "",
                    busy: hasMergeQueue ? "Queueing" : "Merging",
                    systemImage: "arrow.triangle.merge",
                    action: onMerge,
                )
                .hoverHelp(
                    hasMergeQueue
                        ? "Checks passed and the branch is mergeable: queue now"
                        : "Checks passed and the branch is mergeable: merge now",
                )
            } else {
                BusyButton(
                    "",
                    busy: "Enabling automerge",
                    systemImage: "clock.badge.checkmark",
                    action: onAutomerge,
                )
                .hoverHelp("Not mergeable yet: merge automatically once checks and reviews pass")
            }
        }
    }
}
