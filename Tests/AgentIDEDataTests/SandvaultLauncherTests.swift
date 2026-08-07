import AgentIDEData
import Testing

struct SandvaultLauncherTests {
    // MARK: Internal

    @Test
    func `derives sandbox identity from the host user`() {
        #expect(launcher.sandboxUser == "sandvault-mike")
        #expect(launcher.sandboxHome == "/Users/sandvault-mike")
        #expect(launcher.sharedWorkspace == "/Users/Shared/sv-mike")
        #expect(launcher.sandboxProfile == "/var/sandvault/sandbox-sandvault-mike.sb")
    }

    @Test
    func `builds the documented launch shape`() {
        let command = launcher.command(
            payload: "exec tmux ls",
            initialDirectory: "/Users/Shared/sv-mike",
            sessionID: "6E1A0A66-16F5-4EF5-B346-8E561E4D3E71",
            sessionName: "agentide--agentide--app-skeleton--claude",
        )
        #expect(command.first == "sudo")
        #expect(command.contains("--user=sandvault-mike"))
        #expect(command.contains("GIT_CONFIG_VALUE_0=/Users/Shared/sv-mike/*"))
        #expect(command.contains("AGENTIDE_SESSION=agentide--agentide--app-skeleton--claude"))
        #expect(command.contains("/usr/bin/sandbox-exec"))
        #expect(Array(command.suffix(3)) == ["/bin/zsh", "-c", "exec tmux ls"])
    }

    // MARK: Private

    private let launcher: SandvaultLauncher = .init(hostUser: "mike")
}
