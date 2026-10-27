@testable import AgentIDEData
import Foundation
import Testing

struct StartupRegressionTests {
    // MARK: Internal

    @Test
    func `finder launches can find manually installed tools`() {
        #expect(ProcessEnvironment.scrubbed()["PATH"]?.split(separator: ":").contains("/usr/local/bin") == true)
    }

    @Test(arguments: [
        ("/toolchain/libclang_rt.tsan_osx_dynamic.dylib", nil),
        ("/toolchain/libclang_rt.tsan_osx_dynamic.dylib:/other.dylib", "/other.dylib"),
        ("/first.dylib:/toolchain/libclang_rt.tsan_osx_dynamic.dylib:/last.dylib", "/first.dylib:/last.dylib"),
        ("/other.dylib", "/other.dylib"),
    ] as [(String, String?)])
    func `external tools omit the test sanitizer and keep other preloads`(libraries: String, expected: String?) {
        #expect(ProcessEnvironment.scrubbed(merging: ["DYLD_INSERT_LIBRARIES": libraries])["DYLD_INSERT_LIBRARIES"]
            == expected)
    }

    @Test
    func `sandbox launches never ask for a sudo password`() {
        let command = SandvaultLauncher(hostUser: "test").command(
            payload: "true", initialDirectory: "/Users/Shared/sv-test", sessionID: "test", sessionName: "test",
        )
        #expect(command.contains("--non-interactive"))
    }

    @Test
    func `cloning the first repository creates its parent directory`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try FileManager.default.removeItem(atPath: world.paths.repositoriesDirectory)
        let runner = DirectoryRunner()
        let service = SessionService(
            paths: world.paths,
            git: GitClient(runner: runner),
            herdr: world.herdr,
            github: GitHubClient(runner: runner) { true },
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: world.paths.eventsDirectory),
            store: MetadataStore(file: world.paths.metadataFile),
            runners: [],
        )
        _ = try await service.cloneRepository(fullName: "owner/repo")
        #expect(FileManager.default.fileExists(atPath: world.paths.repositoriesDirectory))
    }

    // MARK: Private

    private struct DirectoryRunner: ProcessRunner {
        func run(
            _: [String], workingDirectory: String?, environment _: [String: String], outputLimit _: Int?,
        ) throws -> ProcessResult {
            let directory = try #require(workingDirectory)
            #expect(FileManager.default.fileExists(atPath: directory))
            return ProcessResult(status: 0, standardOutput: "", standardError: "")
        }
    }
}
