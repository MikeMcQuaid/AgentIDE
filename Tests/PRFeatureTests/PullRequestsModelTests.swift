import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Synchronization
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
    func `push needs unpushed commits and the form needs no open pull request`() async {
        let pushed = makeModel(items: [item(branch: "feature", ahead: 0)])
        await pushed.reload()
        #expect(pushed.canPush == false)
        #expect(pushed.needsCreateForm)

        let ahead = makeModel(items: [item(branch: "feature", ahead: 2)])
        #expect(ahead.canPush)

        let unpushed = makeModel(items: [item(branch: "feature", ahead: nil)])
        #expect(unpushed.canPush)

        let open = makeModel(items: [item(branch: "feature", ahead: 1)])
        open.fetchList = { _, _ in [summary(7, head: "feature")] }
        await open.reload()
        #expect(open.needsCreateForm == false)

        let merged = makeModel(items: [item(branch: "feature", ahead: 1)])
        merged.fetchList = { _, _ in [summary(7, head: "feature", state: "MERGED")] }
        await merged.reload()
        #expect(merged.needsCreateForm)

        let elsewhere = makeModel()
        #expect(elsewhere.canPush == false)
        #expect(elsewhere.needsCreateForm == false)
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
    func `every scope asks for one small listing and no more`() async {
        let model = makeModel()
        let asked = Mutex([Int]())
        model.fetchList = { _, limit in
            asked.withLock { $0.append(limit) }
            return (1 ... limit).map { summary($0, head: "branch-\($0)") }
        }
        await model.reload()
        #expect(model.fetchedLimit == GitHubClient.listLimit)

        // Paging walks what is here rather than fetching further
        // into a repository with thousands of open pull requests.
        model.page = 1
        try? await Task.sleep(for: .milliseconds(50))
        #expect(asked.withLock { $0 } == [GitHubClient.listLimit])
    }

    @Test
    func `the default branch is not searched for a pull request of its own`() async {
        let model = makeModel()
        let asked = Mutex(0)
        model.fetchList = { _, _ in
            asked.withLock { $0 += 1 }
            return []
        }
        model.currentBranch = "main"
        await model.reload()
        #expect(asked.withLock { $0 } == 0)

        model.currentBranch = "feature"
        await model.reload()
        #expect(asked.withLock { $0 } == 1)
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
    func `creating a pull request appends the template, never pushes`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var pushed = false
        model.performPush = { _ in
            pushed = true
            return .origin
        }
        var created: (title: String, body: String)?
        model.performCreate = { _, title, body in
            created = (title, body)
            return "https://example.invalid/pull/1"
        }
        model.prTitle = "A change"
        model.prBody = "Why it changed."
        model.prTemplate = "- [ ] Checked"
        #expect(model.isFullyPushed)
        #expect(await model.createPullRequest())
        #expect(pushed == false)
        #expect(created?.title == "A change")
        #expect(created?.body == "Why it changed.\n\n- [ ] Checked")
        #expect(model.prTitle.isEmpty)

        // Unpushed commits dim Open PR instead of pushing for it.
        #expect(makeModel(items: [item(branch: "feature", ahead: 1)]).isFullyPushed == false)

        let untitled = makeModel(items: [item(branch: "feature", ahead: 0)])
        #expect(await untitled.createPullRequest() == false)
    }

    @Test
    func `generating fills blank fields and completes the template`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchCommitMessages = { _ in ["First change\n\nWhy one.", "Second change"] }
        model.generateDescription = { _ in ("Drafted title", "Drafted body") }
        model.fillTemplate = { _, template in "filled: " + template }
        model.prTemplate = "- [ ] Checked"
        #expect(await model.generateDescription())
        #expect(model.prTitle == "Drafted title")
        #expect(model.prBody == "Drafted body")
        #expect(model.prTemplate == "filled: - [ ] Checked")

        // Without a repository template nothing is invented.
        let bare = makeModel(items: [item(branch: "feature", ahead: 1)])
        bare.fetchCommitMessages = { _ in ["Only change\n\nWhy."] }
        bare.fillTemplate = { _, _ in "should never be asked" }
        #expect(await bare.generateDescription())
        #expect(bare.prTitle == "Only change")
        #expect(bare.prBody == "Why.")
        #expect(bare.prTemplate.isEmpty)
    }

    @Test
    func `refreshing a summary updates the header and row`() async {
        let model = makeModel()
        model.fetchList = { _, _ in [summary(3, head: "feature")] }
        await model.reload()
        #expect(model.selected?.number == 3)

        model.fetchSummary = { _ in
            PullRequestSummary(
                number: 3,
                title: "Refreshed",
                url: "",
                headBranch: "feature",
                mergeable: "MERGEABLE",
                reviewDecision: "APPROVED",
                checks: "SUCCESS",
                baseBranch: "main",
                state: "OPEN",
            )
        }
        await model.refreshSummary(3)
        #expect(model.selected?.title == "Refreshed")
        #expect(model.summaries.first?.reviewDecision == "APPROVED")
    }

    @Test
    func `an immediate merge cleans up, arming automerge does not`() async {
        let mergeable = PullRequestSummary(
            number: 5,
            title: "Ready",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
        )
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var cleaned: String?
        model.performPostMergeCleanup = { _, branch in cleaned = branch }
        model.selected = mergeable
        await model.performMergeAction()
        #expect(cleaned == "feature")

        let pending = makeModel(items: [item(branch: "feature", ahead: 0)])
        var pendingCleaned = false
        pending.performPostMergeCleanup = { _, _ in pendingCleaned = true }
        pending.selected = summary(6, head: "feature")
        await pending.performMergeAction()
        #expect(pendingCleaned == false)
    }
}
