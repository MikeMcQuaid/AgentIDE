import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import TerminalUI
import Testing

/// Opening a pull request tells the sidebar at once: both surfaces
/// read one per-branch cache, so the row learns the number and state
/// without waiting for a poll. Split from the model tests for length.
extension PullRequestsModelTests {
    @Test(arguments: [false, true])
    func `opening assigns closing issues without losing a created PR on assignment failure`(fails: Bool) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var actions = [String]()
        var assignedURL: String?
        let (assignments, assigned) = AsyncStream<Void>.makeStream()
        defer { assigned.finish() }
        model.performCreate = { _, _, body, _, _ in
            #expect(body == "Fixes #24324")
            actions.append("create")
            return "https://github.com/o/r/pull/42"
        }
        model.performAssignClosingIssues = { url in
            #expect(model.isOpening == false)
            #expect(model.selected?.number == 42)
            assigned.yield()
            actions.append("assign")
            assignedURL = url
            if fails {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        model.performLinkStack = { _ in actions.append("stack") }
        model.prTitle = "A change"
        model.prBody = "Fixes #24324"

        #expect(await model.createPullRequest())
        var iterator = assignments.makeAsyncIterator()
        for _ in 0 ..< (fails ? 2 : 1) {
            _ = await iterator.next()
        }
        #expect(actions == (fails ? ["create", "stack", "assign", "assign"] : ["create", "stack", "assign"]))
        #expect(assignedURL == "https://github.com/o/r/pull/42")
        #expect(model.selected?.number == 42)
        #expect(model.prTitle.isEmpty)
    }

    @Test
    func `slow issue assignment leaves the created pull request usable`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        let (started, start) = AsyncStream<Void>.makeStream()
        let (waiting, release) = AsyncStream<Void>.makeStream()
        defer {
            start.finish()
            release.finish()
        }
        model.performCreate = { _, _, _, _, _ in "https://github.com/o/r/pull/42" }
        model.performAssignClosingIssues = { _ in
            start.yield()
            for await _ in waiting {
                break
            }
        }
        model.prTitle = "A change"
        let opening = Task {
            await model.createPullRequest()
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        #expect(model.isOpening == false)
        #expect(model.selected?.number == 42)
        #expect(model.prTitle.isEmpty)
        release.yield()
        #expect(await opening.value)
    }

    @Test
    func `failed creation never assigns an issue`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.performCreate = { _, _, _, _, _ in throw CocoaError(.fileWriteNoPermission) }
        var assigned = false
        model.performAssignClosingIssues = { _ in assigned = true }
        model.prTitle = "A change"
        model.prBody = "Fixes #24324"

        #expect(await model.createPullRequest() == false)
        #expect(assigned == false)
        #expect(model.prBody == "Fixes #24324")
    }

    @Test
    func `the draft toggle opens a draft and is remembered`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var openedAsDraft = false
        model.performCreate = { _, _, _, _, isDraft in
            openedAsDraft = isDraft
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        model.prTitle = "A change"
        model.prIsDraft = true

        #expect(await model.createPullRequest())

        // What the form said reaches `gh`, and the row shows the
        // draft's own glyph before any fetch has been near it.
        #expect(openedAsDraft)
        #expect(model.selected?.isDraft == true)
    }

    @Test
    func `opening a pull request lands it in the shared branch cache`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.performCreate = { _, _, _, _, _ in "https://github.com/o/r/pull/42" }
        model.prTitle = "A change"
        await model.reload()
        let before = UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey)

        #expect(await model.createPullRequest())

        // The row reads this, so it paints the moment the form is
        // answered rather than at the next poll.
        let cached = model.pullRequests.branchSummary(repositoryPath: model.repository.path, branch: "feature")
        #expect(cached?.number == 42)
        #expect(cached?.state == "OPEN")
        #expect(cached?.headBranch == "feature")
        // And the sidebar is told to repaint from it.
        #expect(UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey) > before)
    }

    @Test
    func `the listing's own answer beats the one the form assembled`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.performCreate = { _, _, _, _, _ in "https://github.com/o/r/pull/42" }
        // GitHub has it already: its answer carries the checks and
        // mergeability the form could not know.
        let listed = PullRequestSummary(
            number: 42,
            title: "A change",
            url: "https://github.com/o/r/pull/42",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
        )
        model.fetchList = { _, _ in [listed] }
        model.prTitle = "A change"

        #expect(await model.createPullRequest())
        let cached = model.pullRequests.branchSummary(repositoryPath: model.repository.path, branch: "feature")
        #expect(cached?.checks == "SUCCESS")
        #expect(cached?.mergeable == "MERGEABLE")
    }
}
