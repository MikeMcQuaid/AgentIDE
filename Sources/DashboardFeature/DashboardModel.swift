import AgentIDEData
import AgentIDEDomain
import Observation
import UserNotifications

/// The dashboard's state: repositories, worktrees, sessions and
/// archives, refreshed by polling and notifying on completion.
@preconcurrency
@Observable
@MainActor
public final class DashboardModel {
    // MARK: Lifecycle

    /// Creates the model.
    public init(service: SessionService, store: MetadataStore) {
        self.service = service
        self.store = store
    }

    deinit {
        // The polling task is cancelled by its owning view.
    }

    // MARK: Public

    /// The grouped worktrees per repository.
    public private(set) var groups: [RepositoryGroup] = []

    /// Sessions not created by AgentIDE.
    public private(set) var foreign: [AgentSession] = []

    /// Archives available to undelete.
    public private(set) var archives: [ArchiveMetadata] = []

    /// The selected worktree item.
    public var selection: WorktreeItem?

    /// Whether the new session sheet is shown.
    public var showsNewSession = false

    /// The last background error, for display.
    public private(set) var status: String?

    /// The repositories available for new sessions.
    public var repositories: [Repository] {
        service.repositories()
    }

    /// Reloads everything and notifies about newly finished or
    /// newly unread sessions.
    public func refresh() async {
        let overview = await service.overview()
        notifyChanges(from: groups, to: overview.groups)
        groups = overview.groups
        foreign = overview.foreign
        archives = store.load().archives
        if let selected = selection {
            selection = overview.groups.flatMap(\.items).first { $0.id == selected.id }
        }
    }

    /// Polls the system on an interval while the dashboard is alive.
    public func poll() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        while Task.isCancelled == false {
            await refresh()
            try? await Task.sleep(for: .seconds(Self.pollInterval))
        }
    }

    /// Creates a session from the sheet's input.
    public func createSession(
        repository: Repository,
        prompt: String,
        agent: AgentKind,
        extraArguments: String = "",
    ) async {
        do {
            _ = try await service.createSession(
                repository: repository,
                prompt: prompt,
                agent: agent,
                extraArguments: extraArguments,
            )
            showsNewSession = false
            await refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    /// Archives and deletes a worktree.
    public func archive(item: WorktreeItem) async {
        do {
            _ = try await service.archiveAndDelete(item: item)
            if selection?.id == item.id {
                selection = nil
            }
            await refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    /// Restores an archived worktree.
    public func undelete(archive: ArchiveMetadata) async {
        do {
            try await service.undelete(archive: archive)
            await refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: Private

    private static let pollInterval = 5

    private let service: SessionService
    private let store: MetadataStore

    private func notifyChanges(from old: [RepositoryGroup], to new: [RepositoryGroup]) {
        // Uniquing, not trapping: duplicate ids would crash the poll.
        let oldItems = Dictionary(old.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        for item in new.flatMap(\.items) {
            guard let session = item.session, let previous = oldItems[item.id] else {
                continue
            }

            let finished = previous.session?.status == .running && session.status != .running
            let becameUnread = previous.hasUnread == false && item.hasUnread
            guard finished || becameUnread else {
                continue
            }

            post(
                title: finished ? "Agent finished" : "Agent output",
                body: "\(item.worktree.repositoryName): \(item.worktree.branch)",
            )
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request)
    }
}
