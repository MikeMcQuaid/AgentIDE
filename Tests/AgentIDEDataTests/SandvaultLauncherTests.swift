import AgentIDEData
import Testing

struct SandvaultLauncherTests {
    // MARK: Internal

    @Test
    func `derives sandbox identity from the host user`() {
        #expect(launcher.sandboxUser == "sandvault-tester")
        #expect(launcher.sandboxHome == "/Users/sandvault-tester")
        #expect(launcher.sharedWorkspace == "/Users/Shared/sv-tester")
        #expect(launcher.sandboxProfile == "/var/sandvault/sandbox-sandvault-tester.sb")
    }

    @Test
    func `builds the documented launch shape`() {
        let command = launcher.command(
            payload: "exec herdr workspace list",
            initialDirectory: "/Users/Shared/sv-tester",
            sessionID: "6E1A0A66-16F5-4EF5-B346-8E561E4D3E71",
            sessionName: "agentide--agentide--app-skeleton--claude",
        )
        #expect(command.first == "sudo")
        #expect(command.contains("--user=sandvault-tester"))
        #expect(command.contains("GIT_CONFIG_VALUE_0=/Users/Shared/sv-tester/*"))
        #expect(command.contains("AGENTIDE_SESSION=agentide--agentide--app-skeleton--claude"))
        #expect(command.contains("/usr/bin/sandbox-exec"))
        #expect(Array(command.suffix(3)) == ["/bin/zsh", "-c", "exec herdr workspace list"])
    }

    @Test
    func `injected PATH includes Homebrew, where herdr and agents live`() {
        let command = launcher.command(
            payload: "exec herdr workspace list",
            initialDirectory: "/Users/Shared/sv-tester",
            sessionID: "6E1A0A66-16F5-4EF5-B346-8E561E4D3E71",
            sessionName: "agentide--agentide--app-skeleton--claude",
        )
        let path = try? #require(command.first { $0.hasPrefix("PATH=") })
        #expect(path?.contains("/opt/homebrew/bin") == true)
        #expect(path?.contains("/usr/local/bin") == true)
        #expect(path?.contains("/usr/bin") == true)
    }

    // MARK: Private

    private let launcher: SandvaultLauncher = .init(hostUser: "tester")
}
