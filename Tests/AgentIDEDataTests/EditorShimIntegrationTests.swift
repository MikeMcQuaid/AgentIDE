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
    func `without waiting a file is asked for and the command returns at once`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-open")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)
        let file = root + "/notes.md"
        try "notes\n".write(toFile: file, atomically: true, encoding: .utf8)

        let process = try run(shim, arguments: ["notes.md"], in: root)
        try await exit(of: process)
        #expect(process.terminationStatus == 0)

        // The request outlives the command that made it, since
        // nothing is waiting to be answered.
        let edit = try #require(spool.pending().first)
        #expect(edit.kind == .open)
        #expect(edit.path == file)
        #expect(edit.waitsForAnswer == false)
    }

    @Test
    func `anywhere inside a worktree selects it, and outside the workspace is refused`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-select")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)
        let shared = paths(root: root).sharedWorkspace
        let worktree = shared + "/worktrees/brew/fix_it"
        // Deep inside the worktree: the row is what gets selected.
        let inside = worktree + "/Sources/Deep"
        // Under the workspace, but no row above it.
        let outside = shared + "/worktrees"
        for directory in [inside, outside] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        let selecting = try run(shim, arguments: [inside], in: root, sharedWorkspace: shared)
        try await exit(of: selecting)
        #expect(selecting.terminationStatus == 0)
        let edit = try #require(spool.pending().first)
        #expect(edit.kind == .select)
        #expect(edit.path == worktree)

        let refused = try run(shim, arguments: [outside], in: root, sharedWorkspace: shared)
        try await exit(of: refused)
        #expect(refused.terminationStatus == 66)
        #expect(spool.pending().count == 1)
    }

    @Test
    func `a directory of your own is selected from anywhere inside it`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-listed")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)
        let spool = ExternalEditSpool(directory: paths(root: root).editsDirectory)
        let shared = paths(root: root).sharedWorkspace
        let listed = root + "/opt/homebrew"
        try FileManager.default.createDirectory(
            atPath: listed + "/Library/Deep",
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(atPath: shared + "/agentide", withIntermediateDirectories: true)
        try (listed + "\n").write(
            toFile: shared + "/agentide/host-directories",
            atomically: true,
            encoding: .utf8,
        )

        let selecting = try run(shim, arguments: [listed + "/Library/Deep"], in: root, sharedWorkspace: shared)
        try await exit(of: selecting)
        #expect(selecting.terminationStatus == 0)
        #expect(spool.pending().first?.path == listed)
    }

    @Test
    func `help is offered, and printed for anything it cannot make sense of`() async throws {
        let root = try TestSupport.temporaryDirectory("shim-help")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let shim = shim(root: root)

        let helping = try run(shim, arguments: ["--help"], in: root)
        try await exit(of: helping)
        #expect(helping.terminationStatus == 0)

        for arguments in [["--nonsense"], []] {
            let refused = try run(shim, arguments: arguments, in: root)
            try await exit(of: refused)
            #expect(refused.terminationStatus == 64)
        }
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

    private func run(
        _ shim: EditorShim,
        arguments: [String],
        in directory: String,
        sharedWorkspace: String? = nil,
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shim.path)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var environment = shim.environment
        // The command judges a directory against this workspace, and
        // the tests own one of their own; without it the checkout's
        // real workspace would judge the scratch directories.
        environment["SHARED_WORKSPACE"] = sharedWorkspace ?? (directory + "/nowhere")
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
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
