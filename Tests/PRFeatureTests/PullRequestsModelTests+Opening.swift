import Foundation
@testable import PRFeature
import SanductorData
import SanductorDomain
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [SessionService.RebaseNeed.nothing, .sign, .rebase, .rebaseAndSign], [false, true])
    func `opening prepares and pushes unpublished branches`(need: SessionService.RebaseNeed, draft: Bool) async {
        let model = makeModel(items: [item(branch: "feature", ahead: nil)])
        var actions = [String]()
        var signed = need == .nothing || need == .rebase
        model.fetchRebaseNeed = { _ in actions.isEmpty ? need : .nothing }
        model.checkTipSigned = { _ in signed }
        model.performRebase = { _ in
            #expect(model.isOpening)
            actions.append("prepare")
            signed = true
            return "origin/main"
        }
        model.performPush = { _ in
            #expect(model.isOpening)
            actions.append("push")
            return .origin
        }
        model.performCreate = { worktree, title, body, labels, isDraft in
            #expect(worktree.branch == "feature")
            #expect(title == "My title")
            #expect(body == "My body")
            #expect(labels == ["bug"])
            #expect(isDraft == draft)
            #expect(model.isFullyPushed)
            actions.append("open")
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        model.prTitle = "My title"
        model.prBody = "My body"
        model.prLabels = ["bug"]
        model.prIsDraft = draft

        #expect(model.canOpenPullRequest)
        #expect(await model.createPullRequest())
        #expect(actions == (need == .nothing ? ["push", "open"] : ["prepare", "push", "open"]))
        #expect(model.isOpening == false)
    }

    @Test(arguments: ["prepare", "push", "unsigned"], [false, true])
    func `opening distinguishes reported failures from handled refusals`(failure: String, draft: Bool) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchRebaseNeed = { _ in failure == "prepare" ? .rebase : .nothing }
        model.performRebase = { _ in throw CocoaError(.fileWriteNoPermission) }
        model.performPush = { _ in throw CocoaError(.fileWriteNoPermission) }
        var opened = false
        model.performCreate = { _, _, _, _, _ in
            opened = true
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        if failure == "unsigned" {
            var reads = 0
            model.checkTipSigned = { _ in
                reads += 1
                return reads == 1
            }
        }
        model.prTitle = "Keep my title"
        model.prBody = "Keep my body"
        model.prIsDraft = draft

        #expect(await model.createPullRequest() == (failure == "unsigned"))
        if failure == "unsigned" {
            #expect(model.status == "Not pushed: the tip commit is unsigned.")
            #expect(model.isFullyPushed == false)
        }
        #expect(opened == false)
        #expect(model.prTitle == "Keep my title")
        #expect(model.prBody == "Keep my body")
        #expect(model.prIsDraft == draft)
        #expect(model.isOpening == false)
        #expect(model.isBranchActionRunning == false)
    }

    @Test(arguments: [false, true])
    func `opening with missing or guarded work is a handled refusal`(missing: Bool) async {
        let model = makeModel(items: missing ? [] : [item(branch: "main", ahead: 1)])
        await model.reload()
        model.currentBranch = "main"
        model.prTitle = "Keep my title"
        #expect(model.canPublish == false)
        #expect(await model.createPullRequest())
        #expect(model.prTitle == "Keep my title")
        #expect(model.isOpening == false)
        if missing == false {
            #expect(model.status == "Not opened.")
        }
    }

    @Test
    func `opening a pushed branch does not publish again`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var pushed = false
        model.performPush = { _ in
            pushed = true
            return .origin
        }
        await model.reload()
        model.prTitle = "A change"

        #expect(await model.createPullRequest())
        #expect(pushed == false)
    }

    @Test(arguments: [false, true])
    func `opening waits for other actions and cannot run twice`(opening: Bool) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var opened = false
        model.performCreate = { _, _, _, _, _ in
            opened = true
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        model.prTitle = "A change"
        model.isOpening = opening
        model.isBranchActionRunning = opening == false

        #expect(model.canOpenPullRequest == false)
        #expect(await model.createPullRequest())
        #expect(opened == false)
    }

    @Test(arguments: [false, true])
    func `opening a stack entry prepares and pushes the selected branch`(needsRestack: Bool) async {
        let model = makeModel(items: [item(branch: "upper", ahead: 0)], worktreePath: worktreesPath + "/upper")
        var actions = [String]()
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper"),
                outOfPlace: needsRestack && actions.isEmpty ? ["lower"] : [],
                unpushed: actions.contains("push") ? [] : ["lower"],
            )
        }
        model.stacking.restack = { worktree, _ in
            #expect(worktree.branch == "lower")
            actions.append("restack")
            return ["lower", "upper"]
        }
        model.stacking.push = { worktree in
            #expect(worktree.branch == "lower")
            actions.append("push")
            return ["lower"]
        }
        model.performCreate = { worktree, _, _, _, _ in
            #expect(worktree.branch == "lower")
            #expect(model.isFullyPushed)
            actions.append("open")
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        model.prTitle = "Lower work"

        #expect(model.canOpenPullRequest)
        #expect(await model.createPullRequest())
        #expect(actions == (needsRestack ? ["restack", "push", "open"] : ["push", "open"]))
    }
}
