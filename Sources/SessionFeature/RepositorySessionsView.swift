import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The one conversations UI: every conversation of a repository, or
/// of a single worktree when scoped, whether or not its worktree
/// still exists. Selecting one shows its log; any of them can
/// resume here or into a fresh worktree.
public struct RepositorySessionsView: View {
    // MARK: Lifecycle

    /// Creates the browser; `worktreePath` scopes the list to one
    /// worktree, `onNewSession` opens the new session page and
    /// `onResumed` runs after a resume launches.
    @preconcurrency
    public init(
        repository: Repository,
        service: SessionService,
        worktreePath: String? = nil,
        onNewSession: (@MainActor () -> Void)? = nil,
        onResumed: @escaping @MainActor () async -> Void,
    ) {
        self.repository = repository
        self.service = service
        self.worktreePath = worktreePath
        self.onNewSession = onNewSession
        self.onResumed = onResumed
    }

    // MARK: Public

    /// The session list over the selected conversation's log, a
    /// pane-filling progress state while a resume launches, and a
    /// loading state until the first listing answers so the empty
    /// message never flashes before conversations arrive.
    public var body: some View {
        VStack(spacing: 0) {
            if isResuming {
                ProgressView("Resuming conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasLoaded == false {
                ProgressView("Loading conversations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Every agent conversation in this repository appears here, resumable."),
                    )
                } else {
                    list
                    Divider()
                    log
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The worktree scope joins the identity, so switching
        // between worktrees of one repository reloads the list.
        .task(id: repository.id + (worktreePath ?? "")) {
            hasLoaded = false
            await reload()
            hasLoaded = true
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let headerBottomPadding: CGFloat = 3
    private static let agentIconSize: CGFloat = 7
    private static let listHeight: CGFloat = 200
    private static let locationComponents = 2

    @State private var sessions: [(session: TranscriptSession, worktreePath: String)] = []
    @State private var selected: TranscriptSession?
    /// Fills the pane with progress the moment a resume starts.
    @State private var isResuming = false

    /// False until the first listing answers, so the pane shows
    /// loading rather than an empty message that fills in later.
    @State private var hasLoaded = false

    private let repository: Repository
    private let service: SessionService
    private let worktreePath: String?
    private let onNewSession: (@MainActor () -> Void)?
    private let onResumed: @MainActor () async -> Void

    private var selectionBinding: Binding<TranscriptSession?> {
        Binding(get: { selected }, set: { selected = $0 })
    }

    /// The selected conversation's worktree, when it still exists.
    private var selectedWorktreePath: String? {
        guard let selected,
              let path = sessions.first(where: { $0.session.id == selected.id })?.worktreePath,
              FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }

        return path
    }

    private var header: some View {
        HStack {
            Text(worktreePath == nil ? "Conversations in \(repository.name)" : "Conversations in this worktree")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let onNewSession {
                Button("New session", action: onNewSession)
                    .controlSize(.small)
                    .hoverHelp("Start a fresh agent session in this repository instead of resuming")
            }
            Button("Resume here") { resumeSelectedHere() }
                .controlSize(.small)
                .disabled(selectedWorktreePath == nil)
                .hoverHelp(
                    "Continue the selected conversation in the worktree it ran in; dimmed when that worktree is gone",
                )
            Button("Resume in new worktree") { resumeSelected() }
                .controlSize(.small)
                .disabled(selected == nil)
                .hoverHelp("Create a fresh worktree and branch and continue the selected conversation there")
        }
        // Flush with the window's top: the page ignores the toolbar
        // inset, so only a hairline of breathing room remains.
        .padding(.horizontal, Self.padding)
        .padding(.top, Self.headerBottomPadding)
        .padding(.bottom, Self.headerBottomPadding)
    }

    private var list: some View {
        List(sessions, id: \.session.id, selection: selectionBinding) { entry in
            HStack(spacing: Self.padding) {
                Image(entry.session.agent.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.agentIconSize, height: Self.agentIconSize)
                    .accessibilityLabel(entry.session.agent.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    // Untitled conversations borrow their worktree's
                    // name, never the transcript uuid.
                    Text(title(of: entry))
                        .lineLimit(1)
                    HStack(spacing: Self.padding) {
                        Text(
                            Date(timeIntervalSince1970: TimeInterval(entry.session.modifiedAt)),
                            format: .relative(presentation: .named),
                        )
                        Text(location(of: entry.worktreePath))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .tag(entry.session)
            .contextMenu {
                Button("Delete conversation") { delete(entry.session) }
                    .hoverHelp("Remove this conversation's transcript permanently")
            }
        }
        .listStyle(.plain)
        .frame(height: Self.listHeight)
        .hoverHelp("Every conversation in this repository, newest first; pick one to read it below")
    }

    @ViewBuilder private var log: some View {
        if let selected {
            TranscriptLogView(entries: service.transcriptEntries(for: selected))
        } else {
            ContentUnavailableView(
                "No conversation selected",
                systemImage: "text.bubble",
                description: Text("Pick a conversation above to read it."),
            )
        }
    }

    /// The first user prompt, or the worktree's directory name for
    /// untitled conversations.
    private func title(of entry: (session: TranscriptSession, worktreePath: String)) -> String {
        guard entry.session.title.isEmpty else {
            return entry.session.title
        }

        return entry.worktreePath.split(separator: "/").last.map(String.init) ?? "Untitled conversation"
    }

    /// The worktree's readable tail; deleted locations are marked.
    private func location(of path: String) -> String {
        let tail = path.split(separator: "/").suffix(Self.locationComponents).joined(separator: "/")
        let exists = FileManager.default.fileExists(atPath: path)
        return exists ? tail : tail + " (deleted)"
    }

    private func reload() async {
        var all = await service.repositorySessions(for: repository)
        if let worktreePath {
            all = all.filter { $0.worktreePath == worktreePath }
        }
        sessions = all
        selected = sessions.first?.session
    }

    /// Removes a conversation's transcript for good.
    private func delete(_ past: TranscriptSession) {
        Task {
            do {
                try await service.deleteConversation(past)
                await reload()
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
        }
    }

    private func resumeSelected() {
        guard let selected else {
            return
        }

        isResuming = true
        Task {
            do {
                _ = try await service.resumeInNewWorktree(selected, repository: repository)
                await onResumed()
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
            isResuming = false
        }
    }

    /// Resumes the selected conversation in the worktree it ran in;
    /// the branch only names the tmux session, so the path's last
    /// component serves.
    private func resumeSelectedHere() {
        guard let selected, let path = selectedWorktreePath else {
            return
        }

        isResuming = true
        Task {
            do {
                let branch = path.split(separator: "/").last.map(String.init) ?? repository.name
                let worktree = Worktree(
                    repositoryName: repository.name,
                    repositoryPath: repository.path,
                    branch: branch,
                    path: path,
                )
                _ = try await service.resumePast(selected, worktree: worktree)
                await onResumed()
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
            isResuming = false
        }
    }
}
