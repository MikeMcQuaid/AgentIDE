import Foundation

/// Everything needed to restore a deleted worktree and resume its
/// session, stored beside the archive's bundle and tar.
public struct ArchiveMetadata: Codable, Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates archive metadata.
    public init(
        id: String,
        repositoryName: String,
        repositoryPath: String,
        branch: String,
        worktreePath: String,
        sessionName: String,
        resumeID: String?,
        archivedAt: Date,
    ) {
        self.id = id
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.worktreePath = worktreePath
        self.sessionName = sessionName
        self.resumeID = resumeID
        self.archivedAt = archivedAt
    }

    // MARK: Public

    /// The archive directory's name.
    public let id: String

    /// The owning repository's name.
    public let repositoryName: String

    /// The owning repository's checkout path.
    public let repositoryPath: String

    /// The archived branch.
    public let branch: String

    /// The canonical worktree path to restore to, so cwd-keyed
    /// conversation state lines up on resume.
    public let worktreePath: String

    /// The tmux session name the worktree ran under; the agent is
    /// derivable from its suffix.
    public let sessionName: String

    /// The agent-native conversation id used to resume.
    public let resumeID: String?

    /// When the archive was created.
    public let archivedAt: Date
}
