@testable import AgentIDEData
import Foundation
import Testing

// MARK: - AutofixRefreshTests

struct AutofixRefreshTests {
    @Test
    func `slow automation leaves the shared refresh free and coalesces repeated passes`() async throws {
        let fixture = try AutofixFixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.directory) }
        fixture.store.update { $0.pullRequestAutomation[AutofixFixture.key]?.isAutomatic = true }
        let runner = PausedAutomationRunner()
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: fixture.directory,
            sandboxHome: fixture.directory,
            metadataFile: fixture.directory + "/state.json",
        )
        let service = SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(runner: runner, launcher: SandvaultLauncher(hostUser: "test"), isInsideSandbox: true),
            github: GitHubClient(runner: runner) { true },
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: fixture.store,
            runners: [],
        )
        let refresh = Task {
            _ = await service.refreshPullRequestAutomation(groups: [])
            await runner.markReturned()
        }
        #expect(await TestSupport.poll { await runner.isPaused })
        #expect(await TestSupport.poll(timeout: 1) { await runner.refreshReturned })
        _ = await service.refreshPullRequestAutomation(groups: [])
        #expect(await runner.calls == 1)
        await runner.resume()
        await refresh.value
        #expect(await TestSupport.poll {
            fixture.store.load().pullRequestAutomation[AutofixFixture.key]?.pending == "Waiting for the current PR head"
        })
        #expect(await service.refreshPullRequestAutomation(groups: []))
        await service.feedbackCollector.wait("autofix")
    }
}

// MARK: - PausedAutomationRunner

private actor PausedAutomationRunner: ProcessRunner {
    var calls = 0
    var refreshReturned = false
    var continuation: CheckedContinuation<Void, Never>?

    var isPaused: Bool {
        continuation != nil
    }

    func run(
        _: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) async -> ProcessResult {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        return ProcessResult(status: 0, standardOutput: "{}", standardError: "")
    }

    func markReturned() {
        refreshReturned = true
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
