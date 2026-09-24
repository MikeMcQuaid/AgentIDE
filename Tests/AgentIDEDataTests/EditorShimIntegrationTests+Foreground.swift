@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// The shim's foregrounding: a claimed edit asks the system to bring
/// the app it shipped in forward, since the terminal's child may ask
/// where the app asking for itself is refused by cooperative
/// activation. Split from the shim tests for length.
extension EditorShimIntegrationTests {
    @Test(arguments: [ExternalEdit.Kind.edit, .open, .select])
    func `a request brings the app it shipped in forward`(kind: ExternalEdit.Kind) async throws {
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
        let repository = root + "/repositories/repo"
        try FileManager.default.createDirectory(atPath: repository, withIntermediateDirectories: true)
        let process = try run(
            shim(root: root),
            arguments: (kind == .edit ? ["--wait"] : []) + [kind == .select ? repository : root + "/file.txt"],
            in: root,
            sharedWorkspace: root,
            executable: bundled,
            toolDirectory: tools,
        )
        let edit = try #require(await firstEdit(in: spool))
        if kind == .edit {
            // A waiting edit foregrounds only after the app claims it.
            #expect(FileManager.default.fileExists(atPath: opened) == false)
            spool.claim(edit)
        } else {
            try await exit(of: process)
        }
        let raised = await contents(of: opened)
        #expect(raised == root + "/Fake.app")

        if kind == .edit {
            spool.finish(edit, saved: true)
        }
        try await exit(of: process)
        #expect(process.terminationStatus == 0)
    }

    /// A file's trimmed contents, waiting for it to be written.
    /// Waiting for something in it, not for the file: the recording
    /// `open` appends with `>>`, which creates the file a moment
    /// before it writes, and a read in that moment answered empty.
    private func contents(of path: String) async -> String? {
        for _ in 0 ..< Self.waitAttempts {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }

            try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        return nil
    }
}
