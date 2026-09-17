@testable import AgentIDEData
import Foundation
import Testing

/// The hardening's `core.sshCommand`. Split from the client's
/// integration tests for length.
extension GitClientIntegrationTests {
    @Test
    func `an SSH remote reaches ssh, and the repository cannot pick it`() async throws {
        let root = try TestSupport.temporaryDirectory("ssh")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        // `.invalid` never resolves, so ssh fails at its lookup
        // rather than reaching the network or prompting.
        try await TestSupport.runGit(
            ["remote", "add", "origin", "git@example.invalid:owner/repo.git"],
            in: repoPath,
        )

        let ran = root + "/ran"
        let hostile = root + "/hostile.sh"
        try ("#!/bin/sh\ntouch \"" + ran + "\"\nexit 1\n")
            .write(toFile: hostile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostile)
        try await TestSupport.runGit(["config", "core.sshCommand", hostile], in: repoPath)

        let failure = await #expect(throws: Error.self) {
            try await GitClient(runner: FoundationProcessRunner()) { true }
                .fetch(repositoryPath: repoPath)
        }

        #expect(FileManager.default.fileExists(atPath: ran) == false)
        // What a blanked value failed with, before reaching ssh.
        let message = try #require(failure?.localizedDescription)
        #expect(message.contains("cannot run :") == false)
        #expect(message.contains("Could not resolve hostname"))
    }
}
