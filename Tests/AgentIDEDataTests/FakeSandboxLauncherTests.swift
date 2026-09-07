import AgentIDEData
import Synchronization
import Testing

// MARK: - FakeSandboxLauncher

/// A minimal `SandboxLaunching` stand-in for call sites that only
/// need identity and argv capture, not a real sandvault profile.
final class FakeSandboxLauncher: SandboxLaunching, Sendable {
    // MARK: Lifecycle

    init(hostUser: String = "tester") {
        self.hostUser = hostUser
    }

    deinit {
        // Test double; nothing to clean up.
    }

    // MARK: Internal

    let hostUser: String
    let loginShell = "/bin/zsh"
    let detachSuffix = "&!"
    let profileBootstrap = "true; "
    let sandboxPath = "/usr/bin:/bin"

    var sandboxUser: String {
        "sandvault-" + hostUser
    }

    var sandboxHome: String {
        "/tmp/" + sandboxUser
    }

    var sharedWorkspace: String {
        "/tmp/shared-" + hostUser
    }

    var payloads: [String] {
        recorded.withLock { $0 }
    }

    func command(
        payload: String,
        initialDirectory _: String,
        sessionID _: String,
        sessionName _: String,
    ) -> [String] {
        recorded.withLock { $0.append(payload) }
        return [loginShell, "-c", payload]
    }

    // MARK: Private

    private let recorded: Mutex<[String]> = .init([])
}

// MARK: - FakeSandboxLauncherTests

struct FakeSandboxLauncherTests {
    @Test
    func `records payloads without building a sandvault argv`() {
        let launcher = FakeSandboxLauncher()
        let argv = launcher.command(
            payload: "echo hi",
            initialDirectory: "/tmp",
            sessionID: "id",
            sessionName: "name",
        )
        #expect(argv == ["/bin/zsh", "-c", "echo hi"])
        #expect(launcher.payloads == ["echo hi"])
    }
}
