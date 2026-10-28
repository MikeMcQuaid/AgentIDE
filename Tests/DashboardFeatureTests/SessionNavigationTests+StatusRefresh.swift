@testable import DashboardFeature
import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `listing a new agent does not wait for status enrichment`() async throws {
        let runner = HeldStatusRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let path = fixture.repository.path
        try FileManager.default.createDirectory(atPath: path + "/.git", withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(toFile: path + "/.git/HEAD", atomically: true, encoding: .utf8)
        await runner.setRepository(path)
        let summary = PullRequestSummary(
            number: 1, title: "Feature", url: "", headBranch: "feature", mergeable: "", reviewDecision: "", checks: "",
        )
        fixture.model.pullRequests.rememberListing(
            repositoryPath: path,
            scope: .branch("feature"),
            summaries: [summary],
        )
        fixture.model.pullRequests.rememberBranchSummary(summary, repositoryPath: path, branch: "feature")
        fixture.model.isStatusMode = true
        var returned = false
        let refresh = Task {
            await fixture.model.refresh(); returned = true
        }
        for _ in 0 ..< 100 where await runner.isWaiting == false || returned == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await runner.isWaiting)
        #expect(returned)
        await runner.release()
        await refresh.value
        await fixture.model.refreshStatusDetails()
        fixture.model.watchAgentStates([])
    }

    @Test(arguments: [false, true])
    func `phone block edits are acknowledged while status enrichment is held`(removing: Bool) async throws {
        let runner = HeldStatusRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let block = WorkBlock(target: SidebarTarget(item.worktree), scope: .branch, dependency: .note("Waiting"))
        if removing {
            try fixture.model.service.editWorkBlocks(saving: [block], removing: [], groups: fixture.model.groups)
            fixture.model.updateWorkBlocks()
        }
        fixture.model.pullRequests.rememberBranchSummary(
            PullRequestSummary(
                number: 1,
                title: "Feature",
                url: "",
                headBranch: item.worktree.branch,
                mergeable: "",
                reviewDecision: "",
                checks: "",
            ),
            repositoryPath: fixture.repository.path,
            branch: item.worktree.branch,
        )
        let directory = fixture.model.service.sidebarRequestsDirectory
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let requests: [SidebarRequest] = [.refreshStatus, removing ? .remove(block) : .save(block)]
        let paths = try requests.enumerated().map { index, request in
            let path = directory + "/00000000-0000-0000-0000-00000000000" + String(index)
            try JSONEncoder().encode(request).write(to: URL(filePath: path + ".request"), options: .atomic)
            return path + ".response"
        }
        let listener = Task {
            await fixture.model.listenForSidebarRequests()
        }
        for _ in 0 ..< 100 where await runner.isWaiting == false
            || paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) == false
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await runner.isWaiting)
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: path))
            if let data = try? Data(contentsOf: URL(filePath: path)) {
                #expect(try JSONDecoder().decode(SidebarResponse.self, from: data).error == nil)
            }
        }
        #expect(fixture.model.block(for: item) == (removing ? nil : block))
        await runner.release()
        await fixture.model.refreshStatusDetails()
        listener.cancel()
        await listener.value
    }
}

// MARK: - HeldStatusRunner

private actor HeldStatusRunner: ProcessRunner {
    // MARK: Internal

    var isWaiting = false

    func setRepository(_ path: String) {
        repository = path
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) async -> ProcessResult {
        if arguments.contains("gh") {
            if arguments.contains("view"), arguments.contains("pr"), released == false {
                isWaiting = true
                await withCheckedContinuation { waiter = $0 }
            }
            return ProcessResult(status: 1, standardOutput: "", standardError: "Unavailable")
        }
        let output =
            if arguments.contains("worktree"), arguments.contains("list") {
                "worktree " + repository + "\nbranch refs/heads/main\n\nworktree "
                    + repository + "/feature\nbranch refs/heads/feature\n"
            } else if arguments.contains("symbolic-ref") {
                "refs/remotes/origin/main\n"
            } else {
                ""
            }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }

    // MARK: Private

    private var repository = ""
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
}
