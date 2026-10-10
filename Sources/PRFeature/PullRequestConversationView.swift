import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestConversationPane

/// The conversation page: the back button and full header row over
/// the timeline.
struct PullRequestConversationPane: View {
    // MARK: Internal

    let summary: PullRequestSummary
    let stackDepth: Int

    let service: SessionService
    let worktreePath: String?
    let github: GitHubClient
    let repositoryPath: String
    let store: MetadataStore
    let localReview: LocalReview?
    let localWorktreePath: String?
    let onToggleLocalResolved: (String) -> Void

    /// See `PullRequestConversationView.reloadToken`.
    let reloadToken: Int

    let onBack: () -> Void
    let onCopyComments: @MainActor () async -> Void
    let onOpenChecks: @MainActor () async -> Void
    let onResolvedChanged: @MainActor () async -> Void

    /// See `PullRequestConversationView.onThreadsChanged`.
    let onThreadsChanged: @MainActor (Int) -> Void
    let onReviewEventsChanged: @MainActor () -> Void

    /// Opens the title and body for editing.
    var onEdit: (@MainActor () -> Void)?
    var onAskBot: (@MainActor (ReviewBot) async -> Bool)?
    var requestableBots: Set = .init(ReviewBot.allCases)
    var reviewBot: ReviewBot?

    /// Toggles one label against GitHub the moment a menu item is
    /// clicked; declared before the lists so the call site's
    /// closure is never its final argument, which SwiftFormat
    /// would turn into a trailing closure it then mangles.
    let onToggleLabel: @MainActor (String) async -> Void

    /// The pull request's labels and the repository's.
    let labels: [String]
    let availableLabels: [String]

    var body: some View {
        VStack(spacing: 0) {
            header
            FeedbackStatusView(
                service: service, repositoryPath: repositoryPath, worktreePath: worktreePath, summary: summary,
            )
            if labels.isEmpty == false {
                LabelChips(picked: labels)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.labelsPadding)
                    .padding(.bottom, Self.labelsPadding)
            }
            Divider()
            PullRequestConversationView(
                github: github,
                repositoryPath: repositoryPath,
                number: summary.number,
                seededBody: summary.body,
                store: store,
                localReview: localReview,
                localWorktreePath: localWorktreePath,
                onToggleLocalResolved: onToggleLocalResolved,
                reloadToken: reloadToken,
                onResolvedChanged: onResolvedChanged,
                onThreadsChanged: onThreadsChanged,
                onReviewEventsChanged: onReviewEventsChanged,
            )
        }
    }

    // MARK: Private

    private static let labelsPadding: CGFloat = 8

    private var feedback: some View {
        FeedbackView(
            service: service,
            repositoryPath: repositoryPath,
            worktreePath: worktreePath,
            summary: summary,
        )
        .id(summary.url)
    }

    /// The shared header with navigation, labels and autofix controls.
    private var header: some View {
        PullRequestHeaderRow(
            summary: summary,
            stackDepth: stackDepth,
            onBack: onBack,
            onCopyComments: onCopyComments,
            onOpenChecks: onOpenChecks,
            onEdit: onEdit,
            onAskBot: onAskBot,
            requestableBots: requestableBots,
            reviewBot: reviewBot,
            toolbarActions: AnyView(HStack(spacing: Self.labelsPadding) {
                LabelsRow(
                    picked: labels,
                    available: availableLabels,
                    isEnabled: availableLabels.isEmpty == false,
                    help: "Add or remove pull request labels",
                ) { label in Task { await onToggleLabel(label) } }.menu
                feedback
            }),
        )
    }
}

// MARK: - PullRequestConversationView

/// A pull request's conversation: its description, then every review
/// and comment down a timeline rail.
struct PullRequestConversationView: View {
    // MARK: Internal

    let github: GitHubClient
    let repositoryPath: String
    let number: Int

    /// The description already carried by the listing, shown before
    /// any fetch answers.
    let seededBody: String?

    let store: MetadataStore
    let localReview: LocalReview?
    let localWorktreePath: String?
    let onToggleLocalResolved: (String) -> Void

    /// Changed by a refresh asked for by hand, which is what tells
    /// this pane to read its threads and comments again: they are
    /// its own state, and the number alone stays the same across a
    /// refresh of the pull request in view.
    let reloadToken: Int

    /// Runs after a resolve toggle, so the header and listed row
    /// refresh immediately.
    let onResolvedChanged: @MainActor () async -> Void

    /// Told how many conversations are unresolved whenever the
    /// threads change, which keeps the footer's copy button level
    /// with the timeline.
    let onThreadsChanged: @MainActor (Int) -> Void
    let onReviewEventsChanged: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.eventSpacing) {
                if isLoading, events.isEmpty, description.isEmpty, localReview?.threads.isEmpty != false {
                    LaunchProgressView(
                        "Loading the conversation…",
                        waitingOn: "GitHub for the description, reviews and comments of #" + String(number),
                    )
                    .frame(maxWidth: .infinity, minHeight: Self.loadingHeight)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Self.padding)
        }
        // The listing's body or the cached conversation paints
        // instantly (or the state clears, so another pull request's
        // never lingers) while the fetch refreshes and re-caches. A
        // seeded body is fresh from the listing, so only the events
        // need fetching. Failures and cancelled fetches change and
        // cache nothing, keeping the last good conversation.
        .task(id: [number, reloadToken, automationGeneration]) {
            isLoading = true
            defer { isLoading = false }
            let cached = pullRequests.cachedConversation(
                repositoryPath: repositoryPath,
                number: number,
                seededBody: seededBody,
            )
            description = cached.body
            events = cached.events
            threads = cached.threads
            await refresh()
        }
        .onChange(of: events) { onReviewEventsChanged() }
        .onChange(of: threads) { _, threads in
            onThreadsChanged(threads.count { $0.isResolved == false })
            onReviewEventsChanged()
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let eventSpacing: CGFloat = 10
    private static let headerSpacing: CGFloat = 4
    private static let railWidth: CGFloat = 2
    private static let railInset: CGFloat = 10
    private static let loadingHeight: CGFloat = 120

    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var automationGeneration = 0

    @State private var description = ""
    @State private var events: [ReviewComment] = []
    @State private var threads: [ReviewThread] = []
    @State private var isLoading = true

    /// Every question about this pull request goes through the
    /// shared store, which answers from what it already knows unless
    /// a minute has passed since it last asked.
    private var pullRequests: PullRequestStore {
        PullRequestStore(github: github, store: store)
    }

    /// What this read is, for holding its failures apart from every
    /// other repository's #n.
    private var readingWhat: String {
        "Conversation of #" + String(number) + " in " + URL(fileURLWithPath: repositoryPath).lastPathComponent
    }

    @ViewBuilder private var content: some View {
        if description.isEmpty == false {
            MarkdownText(description)
            Divider()
        }
        ForEach(events) { event in
            eventRow(event)
        }
        if threads.isEmpty == false || localReview?.threads.isEmpty == false || isLoading {
            Divider()
            HStack {
                Text("Conversations").interfaceFont(.headline)
                Spacer()
                CopyReviewConversationsButton(threads: threads + (localReview?.threads ?? []))
            }
        }
        // The loading state paints instantly; threads can take a
        // while behind the GraphQL round trip.
        if threads.isEmpty, isLoading {
            ProgressView().controlSize(.small)
        }
        ForEach(threads) { thread in
            ReviewThreadRow(
                thread: thread,
                onEdit: {
                    FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: repositoryPath)
                },
                onToggleResolved: { await toggleResolved(thread) },
                onToggleResolveOnPush: { await toggleResolveOnPush(thread) },
                isPendingResolution: pendingResolution(thread),
            )
        }
        ForEach(localReview?.threads ?? []) { thread in
            ReviewThreadRow(
                thread: thread,
                onEdit: localWorktreePath.map { path in
                    { FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: path) }
                },
                localReviewer: localReview?.reviewer,
                onToggleResolved: { onToggleLocalResolved(thread.id) },
                showsCodeContext: true,
            )
        }
        if events.isEmpty, description.isEmpty, threads.isEmpty,
           localReview?.threads.isEmpty != false, isLoading == false
        {
            Text("No description or feedback yet.")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One timeline entry: the author and review type over the body,
    /// beside the rail.
    private func eventRow(_ event: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            HStack(spacing: Self.headerSpacing) {
                Text(ChecksStyle.authorDisplayName(event.author)).interfaceFont(.callout, weight: .bold)
                if let icon = ChecksStyle.reviewOcticonName(for: event.kind) {
                    Octicon(icon, colour: ChecksStyle.reviewColour(for: event.kind))
                    Text(event.kind.replacing("_", with: " ").lowercased())
                        .interfaceFont(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if event.body.isEmpty == false {
                MarkdownText(event.body)
            }
        }
        .padding(.leading, Self.railInset)
        .overlay(alignment: .leading) {
            Rectangle().fill(.separator).frame(width: Self.railWidth)
        }
    }

    /// Fetches the conversation and its threads, painting over the
    /// cache and re-caching; failures log and the painted cache
    /// stays.
    private func refresh() async {
        do {
            let answer = try await pullRequests.conversation(
                repositoryPath: repositoryPath,
                number: number,
                seededBody: seededBody,
            )
            guard Task.isCancelled == false else {
                return
            }

            if let failure = answer.graphQLFailure {
                PerformanceLog.recordMessage(
                    "Conversations fell back to REST (no resolve buttons): " + failure,
                    isError: false,
                )
            }
            description = answer.body
            events = answer.events
            threads = answer.threads
            ServiceStatus.shared.recordSuccess(doing: readingWhat)
        } catch {
            // The painted cache stays, and the next refresh is the
            // recovery: only a read that fails again is news.
            ServiceStatus.shared.record(failure: error, doing: readingWhat)
        }
    }

    private func pendingResolution(_ thread: ReviewThread) -> Bool {
        _ = automationGeneration
        return pullRequests.pendingResolution(
            repositoryPath: repositoryPath,
            threadID: thread.resolveID,
            number: number,
        )
    }

    private func toggleResolveOnPush(_ thread: ReviewThread) async {
        do {
            try await pullRequests.toggleResolveOnPush(
                repositoryPath: repositoryPath, number: number, threadID: thread.resolveID,
            )
            automationGeneration += 1
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Flips one conversation's resolve state on GitHub, then
    /// refreshes the listing and the header above.
    private func toggleResolved(_ thread: ReviewThread) async {
        do {
            try await github.setThreadResolved(
                repositoryPath: repositoryPath,
                threadID: thread.resolveID,
                resolved: thread.isResolved == false,
            )
            // Resolving is acting, not looking: the store forgets
            // when it last asked so this reads the truth at once.
            pullRequests.invalidate(repositoryPath: repositoryPath, number: number)
            await refresh()
            await onResolvedChanged()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }
}
