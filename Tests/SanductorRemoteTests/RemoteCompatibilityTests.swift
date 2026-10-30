import Foundation
@testable import SanductorRemote
import Testing

struct RemoteCompatibilityTests {
    @Test(arguments: [64, 127])
    func `failed help probes reach the installation guidance`(exitStatus: Int) throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".test-scratch/help-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let command = root.appending(path: "Sanductor command")
        if exitStatus == 64 {
            try "#!/bin/sh\nprintf 'usage: sanductor <file>\\n' >&2\nexit 64\n"
                .write(to: command, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", SSHConfiguration().command(RemoteHerdr.helpCommand(command.path))]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let help = try #require(String(data: data, encoding: .utf8))
        #expect(help.isEmpty == false)
        do {
            try RemoteHerdr.validateCommandHelp(help)
            Issue.record("Accepted an unavailable Mac command")
        } catch {
            #expect(error.localizedDescription.contains("Install the matching Sanductor Mac build"))
        }
    }

    @Test(arguments: ["", "sanductor new", "sanductor repositories"])
    func `old commands require a Mac update instead of reporting no repositories`(help: String) {
        #expect(throws: RemoteError.self) { try RemoteHerdr.validateCommandHelp(help) }
    }

    @Test
    func `the companion accepts commands supporting both mobile operations`() throws {
        try RemoteHerdr.validateCommandHelp("sanductor repositories\nsanductor new --no-attach")
    }
}
