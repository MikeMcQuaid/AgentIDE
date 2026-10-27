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
    static let pageSize: Int = GitHubClient.listLimit

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

    let onStartAgent: StartAgentAction?

    /// Asks the model for the next page, which may fetch it first.
    let onNextPage: @MainActor () async -> Void

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
                if isLoading, pageSummaries.isEmpty {
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
                .disabled(page == 0 || isLoading)
                .hoverHelp("The previous \(Self.pageSize) pull requests")
            // A page still being fetched has no range to name yet.
            if pageSummaries.isEmpty == false {
                Text(String(page * Self.pageSize + 1) + "–" + String(last) + " of " + String(summaries.count))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Next page", systemImage: "chevron.forward") {
                Task {
                    await onNextPage()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(isLoading || (last >= summaries.count && hasMore == false))
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
            onStartAgent: onStartAgent,
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

    /// The arrows the sidebar's own counts use, so a number means
    /// the same thing in both places: up is what has yet to go to
    /// the remote, down what has yet to come from it. A button draws
    /// one of them at most, beside one count.
    static let upArrow = "\u{2191}"

    // swiftformat:disable:next privateSwiftUIDynamicProperties -- Supplied by the parent view.
    @Bindable var model: PullRequestsModel

    /// Shared with the footer's extension files.
    @AppStorage(UtilityTabTarget.pullRequestCacheKey) // swiftformat:disable:next privateSwiftUIDynamicProperties
    var reviewGeneration = 0

    /// The tab signal, shared with the footer's extension files.
    @AppStorage(UtilityTabTarget.key) // swiftformat:disable:next privateSwiftUIDynamicProperties
    var utilityTab = ""

    /// Internal so the copy buttons' own file shares it.
    var interfaceStyle: InterfaceStyle = .init()

    var body: some View {
        HStack {
            branchActions
            if let selected = model.selected {
                copyButtons(for: selected)
            }
            Spacer(minLength: Self.padding)
            if let status = model.status {
                // Selectable so failures can be copied and reported.
                Text(status)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Self.padding)
            draftAndOpenButtons
            if model.isEditing {
                // Saving is the one thing to do while editing.
            } else if let mergeTitle = model.mergeActionTitle {
                BusyButton(
                    mergeTitle,
                    busy: model.mergeActionBusyTitle,
                    systemImage: model.isMergeScheduled ? "checkmark" : nil,
                    prominent: model.isMergeScheduled == false,
                    disabled: model.canMergeAction == false,
                ) {
                    if await model.performMergeAction() == false {
                        utilityTab = UtilityTabTarget.errors
                    }
                }
                .hoverHelp(model.mergeActionHelp)
            }
        }
        .padding(Self.padding)
        .background(.bar)
        .contextMenu {
            if let selected = model.selected {
                CopyPullRequestURLButton(selected.url)
                CopyBranchNameButton(selected.headBranch)
                Divider()
                rawFeedbackMenu(for: selected)
            }
        }
    }

    /// Opening as a draft is its own button beside Open PR: the two
    /// make different pull requests, and a toggle beside them said
    /// which without saying what a click would do.
    var openDraftButton: some View {
        BusyButton(
            openingTitle("Draft"),
            busy: "Opening",
            disabled: openDisabled,
            // The spinner says it is opening; a wider word would
            // widen the button for the whole of its life.
            keepsTitle: true,
        ) {
            model.prIsDraft = true
            if await model.createPullRequest() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp("Rebase, sign and push as needed, then open a draft pull request")
    }

    /// Opening a pull request, and Draft either way: before one
    /// exists it opens a draft, and after it takes the open one
    /// back to being a draft, which work that turned out to need
    /// more is.
    @ViewBuilder var draftAndOpenButtons: some View {
        if model.needsCreateForm {
            openDraftButton
            openButton
        } else if model.isEditing {
            cancelEditButton
            saveEditButton
        } else if model.canConvertToDraft {
            draftButton
        }
    }

    /// Takes the open pull request back to a draft.
    var draftButton: some View {
        BusyButton(
            "Draft",
            busy: "Drafting",
            disabled: model.isBranchActionRunning,
            keepsTitle: true,
        ) {
            if await model.convertToDraft() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp("Take it back to a draft: it stays open, and nobody is asked to review a draft")
    }

    /// One shape for every branch action's title, lone or stacked:
    /// what a click is about to do and the count it is about to
    /// send, or what the last click did while the button stays dim.
    func actionTitle(_ verb: String, arrow: String, count: String, active: Bool, done: String?) -> String {
        if active == false, let done {
            return done
        }

        return count.isEmpty ? verb : verb + " " + arrow + count
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    /// What stops either button opening anything: a title of spaces
    /// dims rather than failing on click, preparation must be available, and
    /// a template still reading exactly as the repository wrote it
    /// helps nobody as a pull request body.
    private var openDisabled: Bool {
        model.canOpenPullRequest == false
    }

    private var openButton: some View {
        BusyButton(
            openingTitle("Open"),
            busy: "Opening",
            prominent: true,
            disabled: openDisabled,
        ) {
            model.prIsDraft = false
            if await model.createPullRequest() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .hoverHelp(
            model.unopenedBelow.map { "Open a pull request for `" + $0 + "` below this branch first" }
                ?? (model.templateUnedited
                    ? "Fill in the template before opening: it still reads as the repository wrote it"
                    : "Rebase, sign and push as needed, then open the pull request with the form's title and body"),
            shortcut: "⌘↩",
        )
    }
}
