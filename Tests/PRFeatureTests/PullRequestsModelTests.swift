import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

/// Exercises the pull request model's listing, pagination, caching
/// and button availability through its fetch seams, so the tab's
/// behaviour tests without GitHub or a window.
struct PullRequestsModelTests {
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
    func `a fresh reload fetches exactly once`() async {
        let model = makeModel()
        var fetches = 0
        model.fetchList = { _, _ in
            fetches += 1
            return [summary(1, head: "feature")]
        }
        await model.reload()
        // reload's own `page = 0` reset must not spawn a second
        // concurrent fetch through page's lookahead observer.
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(fetches == 1)
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
    func `opening a pull request pushes then opens the GitHub page`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchFullName = { "owner/repo" }
        var pushed = false
        model.performPush = { _ in pushed = true }
        #expect(await model.openPullRequestPage())
        #expect(pushed)
        #expect(model.isPushed)
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
}
