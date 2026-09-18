@testable import AgentIDEData
import Foundation
import Testing

struct TestScriptTests {
    @Test
    func `a herdr server without a visible socket does not skip tests`() async throws {
        let root = try TestSupport.temporaryDirectory("test-script")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/script", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/mocks", withIntermediateDirectories: true)
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "script/test")
        try manager.copyItem(at: source, to: URL(filePath: root + "/script/test"))

        for (name, contents) in [
            ("ps", "#!/bin/sh\nprintf '123 herdr server\\n'\n"),
            ("lsof", "#!/bin/sh\nexit 1\n"),
            ("swift", "#!/bin/sh\nprintf 'swift tests reached\\n'\n"),
        ] {
            let path = root + "/mocks/" + name
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        let result = try await FoundationProcessRunner().run(
            ["/bin/bash", root + "/script/test"],
            workingDirectory: root,
            environment: [
                "PATH": root + "/mocks:/usr/bin:/bin:/usr/sbin:/sbin",
                "SV_SESSION_ID": "test-script",
            ],
        )

        #expect(result.succeeded)
        #expect(result.standardOutput.contains("swift tests reached"))
    }
}
