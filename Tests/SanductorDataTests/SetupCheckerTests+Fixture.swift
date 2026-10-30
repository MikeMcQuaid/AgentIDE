import Foundation
@testable import SanductorData
import Synchronization

extension SetupCheckerTests {
    struct Fixture {
        // MARK: Lifecycle

        init() throws {
            root = try TestSupport.temporaryDirectory("setup")
            paths = WorkspacePaths(
                hostUser: "test",
                sharedWorkspace: root + "/shared",
                sandboxHome: root + "/guest",
                metadataFile: root + "/state.json",
            )
            try FileManager.default.createDirectory(atPath: paths.sharedWorkspace, withIntermediateDirectories: true)
            service = SessionService(
                paths: paths,
                git: GitClient(runner: runner),
                herdr: HerdrClient(
                    runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: false,
                ),
                github: GitHubClient(runner: runner) { true },
                transcripts: TranscriptReader(),
                spool: EventSpool(directory: paths.eventsDirectory),
                store: MetadataStore(file: paths.metadataFile),
                runners: [ClaudeCodeRunner(), CodexRunner()],
                processes: runner,
            )
        }

        // MARK: Internal

        let runner: Runner = .init()
        let root: String
        let paths: WorkspacePaths
        let service: SessionService

        var checker: SetupChecker {
            var candidate = SetupChecker(service: service, isInsideSandbox: false, requiresSignedCommits: true)
            candidate.agentBinaryDirectories = [root + "/bin"]
            return candidate
        }

        func close() {
            try? FileManager.default.removeItem(atPath: root)
        }
    }

    final class Runner: ProcessRunner {
        // MARK: Lifecycle

        deinit {
            // No resources to release.
        }

        // MARK: Internal

        let commands: Mutex<[[String]]> = .init([])
        let missing: Mutex<String> = .init("")
        let failure: Mutex<String> = .init("")
        let gitConfiguration: Mutex<String?> = .init(nil)

        func run(
            _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
        ) -> ProcessResult {
            commands.withLock { $0.append(arguments) }
            let problem = failure.withLock { $0 }
            var output = ""
            var status: Int32 = 0
            if arguments.last?.contains("for tool in") == true {
                output = missing.withLock { $0 }
            } else if arguments.first == "git" {
                output = gitConfiguration.withLock { $0 } ?? (problem == "identity" ? "" :
                    "user.name Test\nuser.email test@example.com\n"
                    + (problem == "signing" ? "" : "user.signingkey ~/.ssh/test.pub\n"))
            } else if arguments.last?.hasPrefix("command -v ") == true {
                status = problem == "signing" ? 1 : 0
            } else if arguments.first == "gh" {
                status = problem == "network" ? 1 : 0
            } else if arguments.contains("--list-secret-keys") {
                output = problem == "signing" ? "" : "sec:-:255:22:test\n"
            } else if arguments.last?.contains("gh auth token") == true {
                status = problem == "credentials" ? 1 : 0
            } else if arguments.first == "sudo" {
                status = problem == "sandbox" ? 1 : 0
                output = "sandbox-ready\n" + (problem == "agent" ? "" : "agent=codex\n")
                    + (problem == "keychain" ? "legacy-locked\n" : "no-legacy\n")
            }
            return ProcessResult(status: status, standardOutput: output, standardError: "")
        }
    }
}
