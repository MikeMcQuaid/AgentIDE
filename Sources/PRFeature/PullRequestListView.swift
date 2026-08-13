import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestListView

/// The paginated pull request title list: state icon, number and
/// title per row, each clicking through to its conversation.
struct PullRequestListView: View {
    // MARK: Internal

    /// One fetch page; the tab grows its query limit in these steps.
    static let pageSize = 25

    let summaries: [PullRequestSummary]
    let isLoading: Bool

    /// Whether the last fetch filled its limit, so later pages may
    /// exist beyond what is loaded.
    let hasMore: Bool

    let stackDepth: (PullRequestSummary) -> Int

    /// The selection closure is a non-final property so call sites
    /// keep it labelled; a trailing closure after the multiline call
    /// fights SwiftFormat.
    let onSelect: (PullRequestSummary) -> Void

    @Binding var page: Int

    var body: some View {
        VStack(spacing: 0) {
            List(pageSummaries) { summary in
                row(summary)
            }
            .overlay {
                if isLoading, summaries.isEmpty {
                    ProgressView("Loading pull requests…")
                } else if summaries.isEmpty {
                    ContentUnavailableView("No pull requests", systemImage: "arrow.triangle.pull")
                }
            }
            if summaries.count > Self.pageSize || hasMore {
                Divider()
                pager
            }
        }
    }

    // MARK: Private

    private static let rowSpacing: CGFloat = 4
    private static let pagerSpacing: CGFloat = 8

    private var pageSummaries: [PullRequestSummary] {
        Array(summaries.dropFirst(page * Self.pageSize).prefix(Self.pageSize))
    }

    private var pager: some View {
        let last = min(summaries.count, (page + 1) * Self.pageSize)
        return HStack(spacing: Self.pagerSpacing) {
            Spacer()
            Button("Previous page", systemImage: "chevron.backward") { page -= 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(page == 0)
                .hoverHelp("The previous \(Self.pageSize) pull requests")
            Text(String(page * Self.pageSize + 1) + "–" + String(last) + " of " + String(summaries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Next page", systemImage: "chevron.forward") { page += 1 }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(last >= summaries.count && hasMore == false)
                .hoverHelp("The next \(Self.pageSize) pull requests")
            Spacer()
        }
        .padding(Self.rowSpacing)
    }

    /// The conversation header's own look, without its actions; a
    /// click anywhere outside the inner links opens the conversation.
    private func row(_ summary: PullRequestSummary) -> some View {
        PullRequestRowView(
            summary: summary,
            canRemediate: false,
            stackDepth: stackDepth(summary),
            hasMergeQueue: false,
            showsActions: false,
            onAutomerge: noAction,
            onMerge: noAction,
            onRemediate: noAction,
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(summary) }
        .accessibilityAddTraits(.isButton)
        .hoverHelp("Open this pull request's conversation")
    }

    /// Rows hide their actions but the parameters remain.
    private func noAction() {
        // Never called: the action buttons are not rendered.
    }
}

// MARK: - PullRequestFooterView

/// The pull request tab's footer actions: rebase, push, open,
/// refresh and the status line.
struct PullRequestFooterView: View {
    // MARK: Internal

    let canPush: Bool
    let canOpenPullRequest: Bool
    let canRebase: Bool
    let hasDraft: Bool
    let pushHelp: String
    let status: String?
    let onRebase: () -> Void
    let onPush: () -> Void
    let onOpenPullRequest: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Button("Rebase on origin", action: onRebase)
                .disabled(canRebase == false)
                .hoverHelp(
                    "Fetch, then rebase with --force-rebase --gpg-sign: onto this branch's own origin ref "
                        + "when that is fully signed and only new commits need signatures, "
                        + "otherwise onto origin/HEAD re-signing everything; "
                        + "a conflict aborts and reports to the Errors tab",
                )
            Button("Push", action: onPush)
                .disabled(canPush == false)
                .hoverHelp(pushHelp)
            Button(hasDraft ? "Create PR" : "Open PR", action: onOpenPullRequest)
                .disabled(canOpenPullRequest == false)
                .hoverHelp(openHelp)
            Button("Refresh", action: onRefresh)
                .hoverHelp("Fetch the pull requests again")
            if let status {
                // Selectable so failures can be copied and reported.
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(Self.padding)
        .background(.bar)
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    private var openHelp: String {
        guard canOpenPullRequest else {
            return "This branch already has an open pull request"
        }

        return hasDraft
            ? "Push if needed and open the pull request from the draft's edited title and body"
            : "Write a pull request draft from the repository template and open it in the editor tab"
    }
}

// MARK: - PullRequestScope

/// Which pull requests the tab lists.
enum PullRequestScope: CaseIterable {
    case worktree
    case mine
    case open

    // MARK: Internal

    var title: String {
        switch self {
        case .worktree:
            "Worktree"

        case .mine:
            "Mine"

        case .open:
            "Open"
        }
    }

    /// The client's scope, branch-bound for the worktree case.
    func listScope(branch: String?) -> GitHubClient.ListScope {
        switch self {
        case .worktree:
            .branch(branch ?? "")

        case .mine:
            .mine

        case .open:
            .open
        }
    }
}

// MARK: - PullRequestScopePicker

/// The segmented scope control at the tab's top.
struct PullRequestScopePicker: View {
    // MARK: Internal

    @Binding var scope: PullRequestScope

    var body: some View {
        Picker("Scope", selection: $scope) {
            ForEach(PullRequestScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(Self.padding)
        .hoverHelp(
            "Worktree: this branch's pull requests, open and closed. Mine: open ones you created. Open: every open one",
        )
    }

    // MARK: Private

    private static let padding: CGFloat = 8
}
