import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation
import TerminalUI

/// The conversations pane's state and actions: listing, titles,
/// deletion and the resume flows, kept out of the view so the logic
/// tests without a window. The listing and the file-existence check
/// are stored closures, so tests replace them with fakes.
@preconcurrency
@Observable
@MainActor
final class RepositorySessionsModel {
    // MARK: Lifecycle

    /// Creates the model for one repository; `worktreePath` scopes
    /// the list to one worktree.
    init(repository: Repository, service: SessionService, worktreePath: String?) {
        self.repository = repository
        self.service = service
        self.worktreePath = worktreePath
        listSessions = { await service.repositorySessions(for: repository) }
        fileExists = { FileManager.default.fileExists(atPath: $0) }
    }

    deinit {
        // Tasks are owned by the view's lifetime.
    }

    // MARK: Internal

    let repository: Repository
    let service: SessionService
    let worktreePath: String?

    private(set) var sessions: [(session: TranscriptSession, worktreePath: String)] = []
    var selected: TranscriptSession?

    /// Fills the pane with progress the moment a resume starts.
    private(set) var isResuming = false

    /// False until the first listing answers, so the pane shows
    /// loading rather than an empty message that fills in later.
    private(set) var hasLoaded = false

    /// Test seams: the live service and file system by default.
    var listSessions: () async -> [(session: TranscriptSession, worktreePath: String)]
    var fileExists: (String) -> Bool

    /// The selected conversation's worktree, when it still exists.
    var selectedWorktreePath: String? {
        guard let selected,
              let path = sessions.first(where: { $0.session.id == selected.id })?.worktreePath,
              fileExists(path)
        else {
            return nil
        }

        return path
    }

    /// The first user prompt, or the worktree's directory name for
    /// untitled conversations.
    func title(of entry: (session: TranscriptSession, worktreePath: String)) -> String {
        guard entry.session.title.isEmpty else {
            return entry.session.title
        }

        return entry.worktreePath.split(separator: "/").last.map(String.init) ?? "Untitled conversation"
    }

    /// The worktree's readable tail; deleted locations are marked.
    func location(of path: String) -> String {
        let tail = path.split(separator: "/").suffix(Self.locationComponents).joined(separator: "/")
        return fileExists(path) ? tail : tail + " (deleted)"
    }

    func load() async {
        hasLoaded = false
        await reload()
        hasLoaded = true
    }

    func reload() async {
        var all = await listSessions()
        if let worktreePath {
            all = all.filter { $0.worktreePath == worktreePath }
        }
        sessions = all
        selected = sessions.first?.session
    }

    /// Removes a conversation's transcript for good.
    func delete(_ past: TranscriptSession) {
        Task {
            do {
                try await service.deleteConversation(past)
                await reload()
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
        }
    }

    func resumeSelected(onResumed: @escaping @MainActor () async -> Void) {
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
    func resumeSelectedHere(onResumed: @escaping @MainActor () async -> Void) {
        guard let selected, let path = selectedWorktreePath else {
            return
        }

        isResuming = true
        Task {
            do {
                _ = try await service.resumePast(selected, worktree: resumeWorktree(at: path))
                await onResumed()
            } catch {
                ErrorLog.shared.report(error.localizedDescription)
            }
            isResuming = false
        }
    }

    /// The worktree shape a here-resume launches into: the path's
    /// last component names the branch.
    func resumeWorktree(at path: String) -> Worktree {
        Worktree(
            repositoryName: repository.name,
            repositoryPath: repository.path,
            branch: path.split(separator: "/").last.map(String.init) ?? repository.name,
            path: path,
        )
    }

    // MARK: Private

    private static let locationComponents = 2
}
