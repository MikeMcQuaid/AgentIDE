import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

/// Working in someone else's repository: the branch goes to a fork
/// and the pull request has to say so.
extension PullRequestsModelTests {
    @Test
    func `a push to a fork says whose fork it went to`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        model.performPush = { _ in .fork(owner: "MikeMcQuaid") }
        #expect(await model.push())
        // The button itself says it pushed, and the messages pane
        // keeps where it went: pushing somewhere other than the
        // repository you are looking at is worth knowing later.
        #expect(model.pushDoneTitle == "Pushed")

        // A branch in a fork names its owner too; either way the
        // branch is named, since `gh pr create` left to itself opens
        // a pull request for whatever happens to be checked out.
        #expect(PushDestination.fork(owner: "MikeMcQuaid").head(branch: "feature") == "MikeMcQuaid:feature")
        #expect(PushDestination.origin.head(branch: "feature") == "feature")
    }

    @Test
    func `the checked-out branch drives listing and actions`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "switched" }
        // The service derives a stack around the branch git says is
        // checked out, not the one the sidebar last cached, so an
        // agent switching branches under the app is seen here too.
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["switched"], checkedOut: "switched")
        }
        var listed: GitHubClient.ListScope?
        model.fetchList = { scope, _ in
            listed = scope
            return [summary(1, head: "switched")]
        }
        var pushed: String?
        model.performPush = { worktree in
            pushed = worktree.branch
            return .origin
        }

        await model.reload()
        #expect(listed == .branch("switched"))
        #expect(model.needsCreateForm == false)

        _ = await model.push()
        #expect(pushed == "switched")
    }

    @Test
    func `pushing and rebasing never take back what was typed`() async {
        // One store for both models, so the draft one saves is the
        // draft the other reads.
        let metadataFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-draft-" + UUID().uuidString + ".json")
            .path
        defer { try? FileManager.default.removeItem(atPath: metadataFile) }
        let model = makeModel(items: [item(branch: "feature", ahead: 2)], metadataFile: metadataFile)
        model.prTitle = "A change"
        model.prBody = "Why it matters"
        model.prTemplate = "- [x] Tested"
        // The commit would otherwise fill a form it thinks is empty.
        model.fetchCommitMessages = { _, _ in ["Some commit\n\nIts body"] }

        // Push and rebase both reload the form underneath the user.
        #expect(await model.push())
        #expect(model.prTitle == "A change")
        #expect(model.prBody == "Why it matters")
        #expect(model.prTemplate == "- [x] Tested")

        #expect(await model.rebaseSigned())
        #expect(model.prBody == "Why it matters")
        #expect(model.prTemplate == "- [x] Tested")

        // A reload of a fresh model still restores the draft, which
        // is what the draft is for.
        let reopened = makeModel(items: [item(branch: "feature", ahead: 2)], metadataFile: metadataFile)
        await reopened.reload()
        #expect(reopened.prBody == "Why it matters")
        #expect(reopened.prTemplate == "- [x] Tested")
    }
}
