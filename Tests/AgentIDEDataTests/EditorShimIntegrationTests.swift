@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the real shim script against a real spool, since what
/// matters is that a command run outside the app blocks on it and
/// takes its answer.
struct EditorShimIntegrationTests {
    // MARK: Internal

    @Test
    func `a waiting command blocks until the file is saved and closed`() async throws {
        let root = try TestSupport.temporaryDirectory("shim")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let file = root + "/git-rebase-todo"
        try "pick a1b2c3d Work\n".write(toFile: file, atomically: true, encoding: .utf8)

        let edits = paths(root: root).editsDirectory
        let spool = ExternalEditSpool(directory: edits)
        let process = try run(shim, arguments: ["--wait", "git-rebase-todo"], in: root)
        let edit = try #require(await firstEdit(in: spool))
        #expect(edit.path == file)
        #expect(edit.workingDirectory == root)
        spool.claim(edit)

        // Still waiting: the file is on screen, not dealt with.
        try await Task.sleep(for: .milliseconds(Self.settleMilliseconds))
        #expect(process.isRunning)

        spool.finish(edit, saved: true)
        try await exit(of: process)
        #expect(process.terminationStatus == 0)
        // The shim tidies up after itself, so the app never shows a
        // finished request again.
        #expect(try FileManager.default.contentsOfDirectory(atPath: edits).isEmpty)
    }

    @Test
    func `a cancelled edit fails the command, which aborts a rebase`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-cancel")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)

        let process = try run(shim, arguments: ["-w", root + "/COMMIT_EDITMSG"], in: root)
        let edit = try #require(await firstEdit(in: spool))
        spool.claim(edit)
        spool.finish(edit, saved: false)
        try await exit(of: process)
        #expect(process.terminationStatus != 0)
    }

    @Test
    func `a request whose command has gone is swept rather than shown`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-sweep")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let edits = paths(root: root).editsDirectory
        let spool = ExternalEditSpool(directory: edits)

        let process = try run(shim, arguments: ["--wait", root + "/file.txt"], in: root)
        _ = try #require(await firstEdit(in: spool))
        process.terminate()
        try await exit(of: process)

        #expect(spool.pending().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: edits).isEmpty)
    }

    @Test
    func `a shell pane is told where the shim is and that it is one`() throws {
        let root = try TestSupport.temporaryDirectory("shim-env")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let environment = shim(root: root).environment

        // Every tool splits these on whitespace, so a path with a
        // space in it would break all of them.
        #expect(shim(root: root).path.contains(" ") == false)
        for variable in ["EDITOR", "VISUAL", "GIT_EDITOR"] {
            #expect(environment[variable] == shim(root: root).path + " --wait")
        }
        // A shell that sets its own EDITOR can still find the shim
        // and tell it is running here.
        #expect(environment["PATH"]?.hasPrefix(Self.shimDirectory + ":") == true)
        #expect(environment["AGENTIDE"] == "1")
        #expect(environment["AGENTIDE_EDITS"] == paths(root: root).editsDirectory)
        // The sequence editor is left alone deliberately.
        #expect(environment["GIT_SEQUENCE_EDITOR"] == nil)
    }

    // MARK: Private

    private static let settleMilliseconds = 600
    private static let pollMilliseconds = 50
    private static let waitAttempts = 100

    /// The shim as shipped, run straight from the repository: under
    /// test there is no app bundle to find it in.
    private static let shimDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("bin")
        .path

    private func shim(root: String) -> EditorShim {
        EditorShim(paths: paths(root: root), directory: Self.shimDirectory)
    }

    private func paths(root: String) -> WorkspacePaths {
        WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: root + "/shared",
            sandboxHome: root + "/home",
            metadataFile: root + "/state.json",
            appDirectory: root + "/app",
        )
    }

    private func run(_ shim: EditorShim, arguments: [String], in directory: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shim.path)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment.merging(shim.environment) { _, new in new }
        try process.run()
        return process
    }

    /// The first spooled request, waiting for the shim to write it.
    private func firstEdit(in spool: ExternalEditSpool) async -> ExternalEdit? {
        for _ in 0 ..< Self.waitAttempts {
            if let edit = spool.pending().first {
                return edit
            }

            try? await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        return nil
    }

    private func exit(of process: Process) async throws {
        for _ in 0 ..< Self.waitAttempts where process.isRunning {
            try await Task.sleep(for: .milliseconds(Self.pollMilliseconds))
        }
        #expect(process.isRunning == false)
    }
}
