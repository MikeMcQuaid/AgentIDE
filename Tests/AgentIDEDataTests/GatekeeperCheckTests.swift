@testable import AgentIDEData
import Foundation
import Synchronization
import Testing

// MARK: - ScriptedRunner

/// Answers every command with one output and counts the calls.
private final class ScriptedRunner: ProcessRunner {
    // MARK: Lifecycle

    init(output: String) {
        self.output = output
    }

    deinit {
        // Nothing to release.
    }

    // MARK: Internal

    let output: String
    let calls: Mutex = .init(0)

    func run(_: [String], workingDirectory _: String?, environment _: [String: String]) -> ProcessResult {
        calls.withLock { $0 += 1 }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}

// MARK: - GatekeeperCheckTests

struct GatekeeperCheckTests {
    // MARK: Internal

    @Test
    func `reports quarantined agent files only when the probe dies`() async throws {
        let (binaries, codex) = try Self.makeInstall(quarantined: true)

        let killed = ScriptedRunner(output: "137\n")
        #expect(await GatekeeperCheck(runner: killed, binaryDirectories: [binaries]).blockedFiles() == [codex])

        let allowed = ScriptedRunner(output: "0\n")
        #expect(await GatekeeperCheck(runner: allowed, binaryDirectories: [binaries]).blockedFiles().isEmpty)
    }

    @Test
    func `skips the probe when nothing is quarantined`() async throws {
        let (binaries, _) = try Self.makeInstall(quarantined: false)
        let runner = ScriptedRunner(output: "137\n")

        #expect(await GatekeeperCheck(runner: runner, binaryDirectories: [binaries]).blockedFiles().isEmpty)
        #expect(runner.calls.withLock { $0 } == 0)
    }

    // MARK: Private

    /// A Homebrew-shaped install: `bin/codex` linking into a cask
    /// directory whose real binary is quarantined or not.
    private static func makeInstall(quarantined: Bool) throws -> (binaries: String, codex: String) {
        let root = try TestSupport.temporaryDirectory("gatekeeper")
        let cask = root + "/cask/bin"
        let binaries = root + "/bin"
        try FileManager.default.createDirectory(atPath: cask, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: binaries, withIntermediateDirectories: true)
        let codex = cask + "/codex"
        try "".write(toFile: codex, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: binaries + "/codex", withDestinationPath: codex)
        if quarantined {
            let marker = "0083;00000000;test;"
            let marked = marker.withCString { value in
                setxattr(codex, "com.apple.quarantine", value, marker.utf8.count, 0, 0) == 0
            }
            try #require(marked)
        }
        return (binaries, URL(filePath: codex).resolvingSymlinksInPath().path)
    }
}
