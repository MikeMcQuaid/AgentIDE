/// The privilege-crossing launch shape: how a host process runs a
/// payload as the sandbox user. Mac uses sandvault; Linux will use
/// `agentide-sandbox enter`. Call sites take this protocol so they
/// never reconstruct a concrete launcher.
public protocol SandboxLaunching: Sendable {
    /// The host (GUI) user the sandbox identity is derived from.
    var hostUser: String { get }

    /// The sandbox user that owns herdr and the agent processes.
    var sandboxUser: String { get }

    /// The sandbox user's home directory.
    var sandboxHome: String { get }

    /// The workspace directory both users read and write.
    var sharedWorkspace: String { get }

    /// The login shell that runs payloads inside the sandbox.
    var loginShell: String { get }

    /// How a background server is detached from the launch shell
    /// (zsh's `&!` on Mac; Linux will use `nohup`/`setsid`).
    var detachSuffix: String { get }

    /// Shell statements that load the sandbox user's profile before
    /// starting a long-lived server outside an already-configured
    /// session.
    var profileBootstrap: String { get }

    /// The `PATH` injected into the clean sandbox environment.
    var sandboxPath: String { get }

    /// The full argv that runs `payload` inside the sandbox.
    func command(
        payload: String,
        initialDirectory: String,
        sessionID: String,
        sessionName: String,
    ) -> [String]
}
