@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// The shim tests' harness: building, running and awaiting the real
/// script. In its own file without tests, since SwiftFormat's
/// testSuiteAccessControl would otherwise privatise what the
/// foregrounding tests share.
extension EditorShimIntegrationTests {
    func shim(root: String) -> EditorShim {
        EditorShim(paths: paths(root: root), directory: Self.shimDirectory)
    }

    func paths(root: String) -> WorkspacePaths {
        WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root + "/shared",
            sandboxHome: root + "/home",
            metadataFile: root + "/state.json",
            appDirectory: root + "/app",
        )
    }

    func run(
        _ shim: EditorShim,
        arguments: [String],
        in directory: String,
        sharedWorkspace: String? = nil,
        executable: String? = nil,
        toolDirectory: String? = nil,
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable ?? shim.path)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var environment = shim.environment
        // The command judges a directory against this workspace, and
        // the tests own one of their own; without it the checkout's
        // real workspace would judge the scratch directories.
        environment["SHARED_WORKSPACE"] = sharedWorkspace ?? (directory + "/nowhere")
        if let toolDirectory {
            // Fake tools first, so a recording `open` answers.
            environment["PATH"] = toolDirectory + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        }
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        return process
    }

    /// The first spooled request, waiting for the shim to write it.
    func firstEdit(in spool: ExternalEditSpool) async -> ExternalEdit? {
        for _ in 0 ..< Self.waitAttempts {
            if let edit = spool.pending().first {
                return edit
            }

            try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        return nil
    }

    func exit(of process: Process) async throws {
        for _ in 0 ..< Self.waitAttempts where process.isRunning {
            try await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        #expect(process.isRunning == false)
    }
}
