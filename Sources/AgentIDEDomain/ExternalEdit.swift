import Foundation

/// A file a command outside the app is waiting to have edited: one
/// request from the `agentide` editor shim, which host shells point
/// `EDITOR`, `VISUAL` and `GIT_EDITOR` at.
public struct ExternalEdit: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates a request.
    public init(id: String, path: String, workingDirectory: String, processIdentifier: Int32) {
        self.id = id
        self.path = path
        self.workingDirectory = workingDirectory
        self.processIdentifier = processIdentifier
    }

    /// Decodes one spooled request, whose file name is its id; nil
    /// when the file is not a request this version understands.
    public init?(id: String, json: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: json) else {
            return nil
        }

        self.init(
            id: id,
            path: payload.path,
            workingDirectory: payload.workingDirectory,
            processIdentifier: payload.processIdentifier,
        )
    }

    // MARK: Public

    /// The request's identity, which is its spool file's name.
    public let id: String

    /// The absolute path of the file to edit. It is regularly
    /// outside every worktree: a linked worktree's rebase todo list
    /// lives in the repository's own `.git` directory.
    public let path: String

    /// The directory the command ran in, which locates the worktree
    /// whose pane shows the file.
    public let workingDirectory: String

    /// The shim's process, so a request whose command has gone can
    /// be swept: the shim always waits, so its process being alive
    /// is exactly the request still mattering.
    public let processIdentifier: Int32

    /// The file's name, for the editor's header.
    public var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Whether the command ran inside a worktree, so that the
    /// worktree's editor pane is the one that should show the file.
    public func belongs(toWorktree worktreePath: String) -> Bool {
        workingDirectory == worktreePath || workingDirectory.hasPrefix(worktreePath + "/")
    }

    // MARK: Private

    /// The shim writes exactly these fields.
    private struct Payload: Decodable {
        let path: String
        let workingDirectory: String
        let processIdentifier: Int32
    }
}
