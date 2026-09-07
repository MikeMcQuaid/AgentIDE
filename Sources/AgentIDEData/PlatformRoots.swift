import Foundation

/// The OS-specific directory roots AgentIDE builds every other path
/// from. `detect()` is the single place Mac and Linux layouts diverge.
public struct PlatformRoots: Sendable {
    // MARK: Lifecycle

    /// Creates roots from explicit values.
    public init(
        hostUser: String,
        sharedWorkspace: String,
        sandboxHome: String,
        metadataFile: String,
        sharedTemporaryDirectory: String,
    ) {
        self.hostUser = hostUser
        self.sharedWorkspace = sharedWorkspace
        self.sandboxHome = sandboxHome
        self.metadataFile = metadataFile
        self.sharedTemporaryDirectory = sharedTemporaryDirectory
    }

    // MARK: Public

    /// The host (GUI) user name, with any sandvault prefix stripped.
    public let hostUser: String

    /// The workspace shared by the host and sandbox users.
    public let sharedWorkspace: String

    /// The sandbox user's home directory.
    public let sandboxHome: String

    /// Where the app's own metadata file lives.
    public let metadataFile: String

    /// A temporary directory both users can read, for the performance
    /// log and similar cross-user scratch.
    public let sharedTemporaryDirectory: String

    /// Detects roots for the current process.
    public static func detect() -> Self {
        let user = NSUserName()
        let prefix = "sandvault-"
        let host = user.hasPrefix(prefix) ? String(user.dropFirst(prefix.count)) : user
        #if os(macOS)
            let shared = "/Users/Shared/sv-" + host
            return Self(
                hostUser: host,
                sharedWorkspace: shared,
                sandboxHome: "/Users/sandvault-" + host,
                metadataFile: NSHomeDirectory() + "/Library/Application Support/AgentIDE/state.json",
                sharedTemporaryDirectory: shared + "/tmp/agentide",
            )
        #else
            let shared = "/var/lib/agentide/" + host
            let xdgState = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
                ?? (NSHomeDirectory() + "/.local/state")
            return Self(
                hostUser: host,
                sharedWorkspace: shared,
                sandboxHome: "/home/sandvault-" + host,
                metadataFile: xdgState + "/agentide/state.json",
                sharedTemporaryDirectory: shared + "/tmp/agentide",
            )
        #endif
    }
}
