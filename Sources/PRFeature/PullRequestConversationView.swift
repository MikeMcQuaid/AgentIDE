import AgentIDEData
import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

// MARK: - PullRequestConversationPane

/// The conversation page: the back button and full header row over
/// the timeline.
struct PullRequestConversationPane: View {
    // MARK: Internal

    let summary: PullRequestSummary
    let stackDepth: Int
    let github: GitHubClient
    let repositoryPath: String
    let store: MetadataStore
    let onBack: () -> Void
    let onCopyComments: @MainActor () async -> Void
    let onOpenChecks: @MainActor () async -> Void
    let onResolvedChanged: @MainActor () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.spacing) {
                Button("Back to the list", systemImage: "chevron.backward", action: onBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverHelp("Back to the pull request list")
                PullRequestRowView(
                    summary: summary,
                    stackDepth: stackDepth,
                    showsActions: true,
                    onCopyComments: onCopyComments,
                    onOpenChecks: onOpenChecks,
                )
            }
            .padding(.horizontal, Self.padding)
            // One height however much the summary carries: a light
            // row grows icons as the full fetch lands, and the page
            // jumping under the reader read as a reload.
            .frame(height: Self.headerHeight)
            Divider()
            PullRequestConversationView(
                github: github,
                repositoryPath: repositoryPath,
                number: summary.number,
                seededBody: summary.body,
                store: store,
                onResolvedChanged: onResolvedChanged,
            )
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 8
    private static let headerHeight: CGFloat = 46
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

    /// Runs after a resolve toggle, so the header and listed row
    /// refresh immediately.
    let onResolvedChanged: @MainActor () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.eventSpacing) {
                if isLoading, events.isEmpty, description.isEmpty {
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
        .task(id: number) {
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
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let eventSpacing: CGFloat = 10
    private static let headerSpacing: CGFloat = 4
    private static let railWidth: CGFloat = 2
    private static let railInset: CGFloat = 10
    private static let loadingHeight: CGFloat = 120

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

    @ViewBuilder private var content: some View {
        if description.isEmpty == false {
            MarkdownText(description)
            Divider()
        }
        ForEach(events) { event in
            eventRow(event)
        }
        if threads.isEmpty == false || isLoading {
            Divider()
            HStack {
                Text("Conversations").font(.headline)
                Spacer()
                if threads.contains(where: { $0.isResolved == false }) {
                    Button {
                        copyOpenThreads()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .accessibilityLabel("Copy open conversations")
                    }
                    .buttonStyle(.borderless)
                    .hoverHelp("Copy every open conversation, with its file and line, to the clipboard")
                }
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
            )
        }
        if events.isEmpty, description.isEmpty {
            Text("No description or feedback yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// One timeline entry: the author and review type over the body,
    /// beside the rail.
    private func eventRow(_ event: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: Self.headerSpacing) {
            HStack(spacing: Self.headerSpacing) {
                Text(ChecksStyle.authorDisplayName(event.author)).font(.callout.bold())
                if let icon = ChecksStyle.reviewOcticonName(for: event.kind) {
                    Octicon(icon, colour: ChecksStyle.reviewColour(for: event.kind))
                    Text(event.kind.replacing("_", with: " ").lowercased())
                        .font(.callout)
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
                ErrorLog.shared.report("Conversations fell back to REST (no resolve buttons): " + failure)
            }
            description = answer.body
            events = answer.events
            threads = answer.threads
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Copies every open conversation as pasteable text.
    private func copyOpenThreads() {
        let open = threads.filter { $0.isResolved == false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(open.map(\.asText).joined(separator: "\n\n"), forType: .string)
        ErrorLog.shared.note("Copied \(open.count) open conversations.")
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
