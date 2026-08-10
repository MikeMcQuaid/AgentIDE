import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The repository page: every conversation that ever ran in this
/// repository, whichever worktree it used and whether or not that
/// worktree still exists. Selecting one shows its log; any of them
/// can resume into a fresh worktree.
public struct RepositorySessionsView: View {
    // MARK: Lifecycle

    /// Creates the browser; `onResumed` runs after a resume launches.
    @preconcurrency
    public init(
        repository: Repository,
        service: SessionService,
        onResumed: @escaping @MainActor () async -> Void,
    ) {
        self.repository = repository
        self.service = service
        self.onResumed = onResumed
    }

    // MARK: Public

    /// The session list over the selected conversation's log.
    public var body: some View {
        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: repository.id) { await reload() }
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let headerBottomPadding: CGFloat = 3
    private static let listHeight: CGFloat = 200
    private static let locationComponents = 2

    @State private var sessions: [(session: TranscriptSession, worktreePath: String)] = []
    @State private var selected: TranscriptSession?
    @State private var status: String?

    private let repository: Repository
    private let service: SessionService
    private let onResumed: @MainActor () async -> Void

    private var selectionBinding: Binding<TranscriptSession?> {
        Binding(get: { selected }, set: { selected = $0 })
    }

    private var header: some View {
        HStack {
            Text("Conversations in \(repository.name)")
                .font(.subheadline.weight(.semibold))
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
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
                Image(systemName: entry.session.agent.iconSystemName)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(entry.session.agent.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.session.title.isEmpty ? entry.session.id : entry.session.title)
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

    /// The worktree's readable tail; deleted locations are marked.
    private func location(of path: String) -> String {
        let tail = path.split(separator: "/").suffix(Self.locationComponents).joined(separator: "/")
        let exists = FileManager.default.fileExists(atPath: path)
        return exists ? tail : tail + " (deleted)"
    }

    private func reload() async {
        sessions = await service.repositorySessions(for: repository)
        selected = sessions.first?.session
    }

    private func resumeSelected() {
        guard let selected else {
            return
        }

        Task {
            do {
                _ = try await service.resumeInNewWorktree(selected, repository: repository)
                await onResumed()
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
