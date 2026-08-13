import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

/// Exercises the pull request model's listing, pagination, caching
/// and button availability through its fetch seams, so the tab's
/// behaviour tests without GitHub or a window.
struct PullRequestsModelTests {
    // MARK: Internal

    @Test
    func `stack depth follows base branches through listed heads`() async {
        let model = makeModel()
        model.fetchList = { _, _ in
            [
                summary(1, head: "first"),
                summary(2, head: "second", base: "first"),
                summary(3, head: "third", base: "second"),
            ]
        }
        await model.reload()
        #expect(model.stackDepth(for: summary(3, head: "third", base: "second")) == 3)
        #expect(model.stackDepth(for: summary(1, head: "first")) == 1)
    }

    @Test
    func `push needs unpushed commits and opening needs no open pull request`() async {
        let pushed = makeModel(items: [item(branch: "feature", ahead: 0)])
        #expect(pushed.canPush == false)
        #expect(pushed.canOpenPullRequest)

        let ahead = makeModel(items: [item(branch: "feature", ahead: 2)])
        #expect(ahead.canPush)

        let unpushed = makeModel(items: [item(branch: "feature", ahead: nil)])
        #expect(unpushed.canPush)

        let open = makeModel(items: [item(branch: "feature", ahead: 1)])
        open.fetchList = { _, _ in [summary(7, head: "feature")] }
        await open.reload()
        #expect(open.canOpenPullRequest == false)

        let merged = makeModel(items: [item(branch: "feature", ahead: 1)])
        merged.fetchList = { _, _ in [summary(7, head: "feature", state: "MERGED")] }
        await merged.reload()
        #expect(merged.canOpenPullRequest)

        let elsewhere = makeModel()
        #expect(elsewhere.canPush == false)
        #expect(elsewhere.canOpenPullRequest == false)
    }

    @Test
    func `reload keeps the selection and opens single results directly`() async {
        let model = makeModel()
        model.fetchList = { _, _ in [summary(1, head: "one"), summary(2, head: "two")] }
        await model.reload()
        #expect(model.selected == nil)

        model.select(summary(2, head: "two"))
        await model.reload(keepingSelection: true)
        #expect(model.selected?.number == 2)

        await model.reload()
        #expect(model.selected == nil)

        model.fetchList = { _, _ in [summary(9, head: "only")] }
        await model.reload()
        #expect(model.selected?.number == 9)
    }

    @Test
    func `visiting the lookahead page raises the fetch limit`() async {
        let model = makeModel()
        model.fetchList = { _, limit in (1 ... limit).map { summary($0, head: "branch-\($0)") } }
        await model.reload()
        let first = model.fetchedLimit
        #expect(first == 2 * PullRequestListView.pageSize)
        #expect(model.hasMore)

        model.page = 1
        for _ in 0 ..< 200 where model.fetchedLimit == first {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.fetchedLimit == 3 * PullRequestListView.pageSize)
        #expect(model.page == 1)
    }

    @Test
    func `a short answer means no more pages`() async {
        let model = makeModel()
        model.fetchList = { _, _ in [summary(1, head: "one")] }
        await model.reload()
        #expect(model.hasMore == false)
    }

    @Test
    func `the cached listing paints when the fetch fails`() async {
        let file = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-prmodel-" + UUID().uuidString + ".json")
            .path
        defer { try? FileManager.default.removeItem(atPath: file) }

        let model = makeModel(metadataFile: file)
        model.fetchList = { _, _ in [summary(4, head: "cached")] }
        await model.reload()

        let rebuilt = makeModel(metadataFile: file)
        rebuilt.fetchList = { _, _ in throw CocoaError(.fileNoSuchFile) }
        await rebuilt.reload()
        #expect(rebuilt.summaries.map(\.number) == [4])
    }

    @Test
    func `pushing dims the button until new commits arrive`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        #expect(model.canPush)

        #expect(await model.push())
        #expect(model.isPushed)
        #expect(model.canPush == false)
        #expect(model.status == "Pushed.")

        model.items = [item(branch: "feature", ahead: 1)]
        #expect(model.canPush)
    }

    @Test
    func `an unsigned tip dims Push and explains itself`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        model.checkTipSigned = { _ in false }
        await model.reload()
        #expect(model.canPush == false)
        #expect(model.pushHelp.contains("not GPG signed"))

        model.checkTipSigned = { _ in true }
        await model.reload()
        #expect(model.canPush)
    }

    @Test
    func `an unsigned tip with nothing to push reads as pushed`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.checkTipSigned = { _ in false }
        await model.reload()
        #expect(model.pushHelp.contains("already pushed"))
    }

    @Test
    func `a failed push reports rather than dimming`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        model.performPush = { _ in throw CocoaError(.fileNoSuchFile) }
        #expect(await model.push() == false)
        #expect(model.canPush)
    }

    @Test
    func `opening a pull request drafts first and creates second`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        var prepared: String?
        model.prepareDraft = { _, disclosure in
            prepared = disclosure
            return ".agentide-pull-request.md"
        }

        let first = await model.ship(disclosure: "Claude Code")
        guard case let .drafted(relativePath) = first else {
            Issue.record("Expected a draft, got \(first)")
            return
        }

        #expect(relativePath == ".agentide-pull-request.md")
        #expect(prepared == "Claude Code")
        #expect(model.hasDraft)

        let second = await model.ship(disclosure: nil)
        guard case .created = second else {
            Issue.record("Expected creation, got \(second)")
            return
        }

        #expect(model.hasDraft == false)
        #expect(model.isPushed)
        #expect(model.status == "https://example.test/pull/1")
    }

    @Test
    func `the checked-out branch drives listing and actions`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "switched" }
        var listed: GitHubClient.ListScope?
        model.fetchList = { scope, _ in
            listed = scope
            return [summary(1, head: "switched")]
        }
        var pushed: String?
        model.performPush = { worktree in pushed = worktree.branch }

        await model.reload()
        #expect(listed == .branch("switched"))
        #expect(model.canOpenPullRequest == false)

        _ = await model.push()
        #expect(pushed == "switched")
    }

    // MARK: Private

    /// A model against a throwaway store whose every fetch and
    /// service seam is replaced; nothing real is reached by these
    /// tests.
    private func makeModel(
        items: [WorktreeItem] = [],
        metadataFile: String? = nil,
    ) -> PullRequestsModel {
        let runner = FoundationProcessRunner()
        let base = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-prmodel-" + UUID().uuidString, isDirectory: true)
            .path
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: base + "/shared",
            sandboxHome: base + "/home",
            metadataFile: metadataFile ?? base + "/state.json",
        )
        let service = SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            tmux: TmuxClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                socketDirectory: base + "/socket",
            ),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: MetadataStore(file: paths.metadataFile),
            runners: [],
        )
        let model = PullRequestsModel(
            repository: Repository(name: "repo", path: "/repo"),
            branch: "feature",
            items: items,
            github: GitHubClient(runner: runner),
            service: service,
            store: MetadataStore(file: paths.metadataFile),
        )
        model.fetchList = { _, _ in [] }
        model.fetchSummary = { _ in nil }
        model.fetchHasMergeQueue = { false }
        model.fetchRemediationContext = { _ in "" }
        model.fetchCurrentBranch = { _ in nil }
        model.checkDraft = { _ in false }
        model.prepareDraft = { _, _ in ".agentide-pull-request.md" }
        model.createFromDraft = { _ in "https://example.test/pull/1" }
        model.performPush = { _ in
            // Succeeds without side effects.
        }
        model.performRebase = { _ in
            // Succeeds without side effects.
        }
        model.checkTipSigned = { _ in true }
        return model
    }

    private func summary(
        _ number: Int,
        head: String,
        base: String = "main",
        state: String = "OPEN",
    ) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title \(number)",
            url: "",
            headBranch: head,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            baseBranch: base,
            state: state,
        )
    }

    private func item(branch: String, ahead: Int?) -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: "/repo",
                branch: branch,
                path: "/worktrees/" + branch,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: ahead,
            hasUnread: false,
        )
    }
}
