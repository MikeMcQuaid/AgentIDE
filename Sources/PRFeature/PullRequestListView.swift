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
            // Plain rows, not a List: its inset and separator made
            // a row sit a few points off the header it turns into.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pageSummaries) { summary in
                        row(summary)
                        Divider()
                    }
                }
            }
            .overlay {
                if isLoading, summaries.isEmpty {
                    LaunchProgressView(spinner: "Loading pull requests…")
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
        // The conversation's own header, back chevron and all: the
        // chevron is dimmed rather than absent so the title starts
        // at the same x, and the browser button stays, since a row
        // is a pull request whether or not it is open.
        PullRequestHeaderRow(
            summary: summary,
            stackDepth: stackDepth(summary),
            onBack: nil,
            onCopyComments: noAction,
            onOpenChecks: noAction,
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

/// The pull request tab's footer actions in the order they are
/// expected to be clicked: fetch, rebase, push and, when the
/// creation form shows, Open PR as the primary action.
struct PullRequestFooterView: View {
    // MARK: Internal

    @Bindable var model: PullRequestsModel

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage(UtilityTabTarget.key)
    var utilityTab = ""

    /// Sidebar-style: how far the branch sits behind its base.
    var rebaseCount: String {
        let behind = model.branchItem?.behindDefault ?? 0
        return behind > 0 ? "\u{2193}" + String(behind) : ""
    }

    var rebaseHelp: String {
        model.rebaseTitle + ": fetch, then rebase with --force-rebase --gpg-sign onto this branch's "
            + "own origin ref when that is fully signed and only new commits need signatures, "
            + "otherwise onto origin/HEAD re-signing everything; a conflict aborts and reports to Messages"
    }

    var body: some View {
        HStack {
            branchActions
            if let selected = model.selected {
                copyButtons(for: selected)
            }
            if let status = model.status {
                // Selectable so failures can be copied and reported.
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.needsCreateForm {
                openButton
            }
            if model.isStackedEntry {
                mergeStackButton
            } else if let mergeTitle = model.mergeActionTitle {
                BusyButton(mergeTitle, busy: model.mergeActionBusyTitle, prominent: true) {
                    await model.performMergeAction()
                }
                .hoverHelp(
                    "The one merge action for the open conversation: its label names exactly "
                        + "what a click does now, and a second click cancels automerge or queueing",
                )
            }
        }
        .padding(Self.padding)
        .background(.bar)
    }

    var rebaseButton: some View {
        BusyButton(
            rebaseCount,
            busy: "Rebasing",
            systemImage: "arrow.triangle.2.circlepath",
            accessibilityLabel: model.rebaseTitle,
            disabled: model.canRebase == false,
        ) {
            if await model.rebaseSigned() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(rebaseHelp)
    }

    var pushButton: some View {
        BusyButton(
            pushCount,
            busy: "Pushing",
            systemImage: "arrow.up",
            accessibilityLabel: "Push",
            disabled: model.canPush == false,
            keepsTitle: true,
        ) {
            if await model.push() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(model.pushHelp)
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    /// Sidebar-style: how many commits a push would send.
    private var pushCount: String {
        let ahead = model.branchItem?.aheadOfUpstream ?? 0
        return ahead > 0 ? String(ahead) : ""
    }

    private var openButton: some View {
        BusyButton(
            "Open PR",
            busy: "Opening",
            prominent: true,
            // Trimmed like the validation, so a title of spaces
            // dims the button rather than failing on click; the
            // push comes first, explicitly. A body drafted or typed
            // is enough on its own, but a template still reading
            // exactly as the repository wrote it is not: opening
            // with its placeholders intact helps nobody.
            disabled: model.prTitle.trimmingCharacters(in: .whitespaces).isEmpty
                || model.isFullyPushed == false
                || model.templateUnedited
                || model.unpushedBelow != nil,
        ) {
            if await model.createPullRequest() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .hoverHelp(
            model.unpushedBelow.map { "Push and open `" + $0 + "` below this one first" }
                ?? (model.templateUnedited
                    ? "Fill in the template before opening: it still reads as the repository wrote it"
                    : "Open the pull request with the form's title and body (Cmd-Return); dimmed until pushed"),
        )
    }

    /// The copy actions for the open conversation, in the footer's
    /// click-order run.
    @ViewBuilder
    private func copyButtons(for selected: PullRequestSummary) -> some View {
        BusyButton(
            "",
            busy: "",
            systemImage: "text.bubble",
            accessibilityLabel: "Copy unresolved comments",
        ) {
            await model.copyUnresolvedComments(selected)
        }
        .hoverHelp("Copy every unresolved review conversation to the clipboard")
        Button {
            model.openFailingChecks(selected)
        } label: {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityLabel("Open failing checks")
        }
        .hoverHelp("Open the failing check, or the checks page when several fail; Cmd for the system browser")
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

    /// What the worktree scope calls itself: Branch on the main
    /// checkout, where there is no worktree to speak of.
    let worktreeTitle: String

    var body: some View {
        Picker("Scope", selection: $scope) {
            ForEach(PullRequestScope.allCases, id: \.self) { scope in
                Text(scope == .worktree ? worktreeTitle : scope.title).tag(scope)
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
