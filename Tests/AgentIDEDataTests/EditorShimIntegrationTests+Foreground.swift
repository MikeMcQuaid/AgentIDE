@testable import AgentIDEData
import Foundation
import Testing

/// The shim's foregrounding: a claimed edit asks the system to bring
/// the app it shipped in forward, since the terminal's child may ask
/// where the app asking for itself is refused by cooperative
/// activation. Split from the shim tests for length.
extension EditorShimIntegrationTests {
    @Test
    func `a claimed edit brings the app it shipped in forward`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-front")
        defer { try? FileManager.default.removeItem(atPath: root) }
        // The shim judges its bundle from its own location, so give
        // this copy one; the repository's own copy has none, which
        // is what keeps every other test from opening anything.
        let bundled = root + "/Fake.app/Contents/Resources/bin/agentide"
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: bundled).deletingLastPathComponent().path,
            withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(atPath: Self.shimDirectory + "/agentide", toPath: bundled)
        // A recording `open` ahead of the real one: what matters is
        // that the system was asked, and for the right bundle.
        let tools = root + "/tools"
        let opened = root + "/opened"
        try FileManager.default.createDirectory(atPath: tools, withIntermediateDirectories: true)
        try ("#!/bin/sh\nprintf '%s\\n' \"$1\" >>\"" + opened + "\"\n")
            .write(toFile: tools + "/open", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tools + "/open")

        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)
        let process = try run(
            shim(root: root),
            arguments: ["--wait", root + "/file.txt"],
            in: root,
            executable: bundled,
            toolDirectory: tools,
        )
        let edit = try #require(await firstEdit(in: spool))
        // Nothing to bring forward until the app has the file.
        #expect(FileManager.default.fileExists(atPath: opened) == false)

        spool.claim(edit)
        let raised = await contents(of: opened)
        #expect(raised == root + "/Fake.app")

        spool.finish(edit, saved: true)
        try await exit(of: process)
        #expect(process.terminationStatus == 0)
    }

    /// A file's trimmed contents, waiting for it to be written.
    private func contents(of path: String) async -> String? {
        for _ in 0 ..< Self.waitAttempts {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        return nil
    }
}
