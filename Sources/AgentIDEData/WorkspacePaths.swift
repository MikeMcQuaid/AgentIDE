import Foundation

/// The sandvault-related locations AgentIDE reads and writes. The
/// roots are injectable so tests run against temporary workspaces.
public struct WorkspacePaths: Sendable {
    // MARK: Lifecycle

    /// Creates paths from explicit roots.
    public init(
        hostUser: String,
        sharedWorkspace: String,
        sandboxHome: String,
        metadataFile: String,
    ) {
        self.hostUser = hostUser
        self.sharedWorkspace = sharedWorkspace
        self.sandboxHome = sandboxHome
        self.metadataFile = metadataFile
    }

    // MARK: Public

    /// Whether this process runs inside a sandvault session.
    /// Whether this process is the installed app rather than a dev
    /// build or a test runner; the check names the app bundle
    /// because a test runner's `Bundle.main` is Xcode's own harness,
    /// which also lives under /Applications. Dev and test flavours
    /// get their own tmux socket directory and shell name prefix, so
    /// building and testing can never list or kill production
    /// sessions.
    public static let isProductionBuild = Bundle.main.bundlePath.hasPrefix("/Applications/AgentIDE.app")

    public static var isInsideSandbox: Bool {
        ProcessInfo.processInfo.environment["SV_SESSION_ID"] != nil
    }

    /// The host (GUI) user name.
    public let hostUser: String

    /// The workspace shared by the host and sandbox users.
    public let sharedWorkspace: String

    /// The sandbox user's home directory.
    public let sandboxHome: String

    /// Where the app's own metadata file lives.
    public let metadataFile: String

    /// Where full repository checkouts live.
    public var repositoriesDirectory: String {
        sharedWorkspace + "/repositories"
    }

    /// Where canonical uuid-grouped worktrees live.
    public var worktreesDirectory: String {
        sharedWorkspace + "/worktrees"
    }

    /// AgentIDE's own area of the shared workspace.
    public var agentideDirectory: String {
        sharedWorkspace + "/agentide"
    }

    /// Where session prompt files are written.
    public var promptsDirectory: String {
        agentideDirectory + "/prompts"
    }

    /// Where hook events are spooled.
    public var eventsDirectory: String {
        agentideDirectory + "/events"
    }

    /// Where human-friendly worktree symlinks live.
    public var friendlyWorktreesDirectory: String {
        agentideDirectory + "/worktrees"
    }

    /// The template directory sandvault copies into the sandbox home.
    public var userTemplateDirectory: String {
        sharedWorkspace + "/user"
    }

    /// Creates paths for the current process, stripping any sandvault
    /// prefix so the same paths work inside and outside the sandbox.
    public static func current() -> Self {
        let user = NSUserName()
        let prefix = "sandvault-"
        let host = user.hasPrefix(prefix) ? String(user.dropFirst(prefix.count)) : user
        let support = NSHomeDirectory() + "/Library/Application Support/AgentIDE"
        return Self(
            hostUser: host,
            sharedWorkspace: "/Users/Shared/sv-" + host,
            sandboxHome: "/Users/sandvault-" + host,
            metadataFile: support + "/state.json",
        )
    }
}
