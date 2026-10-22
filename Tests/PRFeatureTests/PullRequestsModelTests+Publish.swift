import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [SessionService.RebaseNeed.nothing, .sign, .rebase, .rebaseAndSign])
    func `one action prepares and pushes a standalone branch`(need: SessionService.RebaseNeed) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        var actions = [String]()
        var signed = need == .nothing || need == .rebase
        model.fetchRebaseNeed = { _ in actions.isEmpty ? need : .nothing }
        model.checkTipSigned = { _ in signed }
        model.performRebase = { _ in
            #expect(model.isBranchActionRunning)
            actions.append("rebase")
            signed = true
            return "origin/main"
        }
        model.performPush = { _ in
            #expect(model.isBranchActionRunning)
            actions.append("push")
            return .origin
        }
        await model.reload()
        if need != .nothing {
            model.tipSignature = .unread
        }
        #expect(model.canPublish)
        #expect(model.publishTitle == (need == .nothing ? "Push" : need == .sign ? "Sign and Push" : "Rebase and Push"))
        #expect(await model.publish())
        #expect(actions == (need == .nothing ? ["push"] : ["rebase", "push"]))
        #expect(model.isFullyPushed)
        #expect(model.canPublish == false)
        #expect(model.pushDoneTitle == "Pushed")
    }

    @Test
    func `a failed rebase never pushes and can be retried`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchRebaseNeed = { _ in .rebase }
        model.performRebase = { _ in throw CocoaError(.fileWriteNoPermission) }
        var pushed = false
        model.performPush = { _ in
            pushed = true
            return .origin
        }
        await model.reload()
        #expect(await model.publish() == false)
        #expect(pushed == false)
        #expect(model.canPublish)
        #expect(model.isBranchActionRunning == false)
    }

    @Test
    func `publishing signs a commit amended after the last reading`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        await model.reload()
        var signed = false
        model.checkTipSigned = { _ in signed }
        model.performRebase = { _ in
            signed = true
            return "origin/main"
        }
        #expect(await model.publish())
        #expect(signed)
        #expect(model.isFullyPushed)
    }

    @Test
    func `the combined action waits for facts and guards busy and protected branches`() async {
        let model = makeModel(items: [item(branch: "main", ahead: 1)])
        model.currentBranch = "main"
        #expect(model.canPublish == false)
        await model.reload()
        await model.loadDefaultBranchPolicy()
        var pushed = false
        model.performPush = { _ in
            pushed = true
            return .origin
        }
        #expect(model.canPublish == false)
        #expect(await model.publish())
        #expect(pushed == false)
        #expect(model.status?.contains("default branch") == true)
        model.fetchAcceptsDefaultPushes = { true }
        await model.loadDefaultBranchPolicy()
        model.isBranchActionRunning = true
        #expect(model.canPublish == false)
        #expect(await model.publish())
        #expect(pushed == false)
    }

    @Test(arguments: [false, true])
    func `a newer default branch enables rebase without unpushed commits`(stacked: Bool) async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 0, behind: 0)])
        var moved = false
        var actions = [String]()
        model.fetchRebaseNeed = { _ in moved ? .rebase : .nothing }
        if stacked {
            model.stacking.facts = { _ in
                StackFacts(
                    stack: BranchStack(base: "main", branches: ["feature", "upper"], checkedOut: "feature"),
                    outOfPlace: moved ? ["feature"] : [],
                )
            }
        }
        model.performRebase = { _ in
            actions.append("rebase")
            moved = false
            return "origin/main"
        }
        model.stacking.restack = { _, _ in
            actions.append("rebase")
            moved = false
            return ["feature", "upper"]
        }
        model.performPush = { _ in
            actions.append("push")
            return .origin
        }
        model.stacking.push = { _ in
            actions.append("push")
            return ["feature"]
        }
        await model.reload()
        model.pushedTip = PullRequestsModel.PushedTip(branch: "feature", commit: "tip")
        #expect(model.canPublish == false)

        moved = true
        model.items = [item(branch: "feature", ahead: 0, behind: 2)]
        for _ in 0 ..< 100 where model.rebaseNeed == .nothing {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.canPublish)
        #expect(model.publishTitle == "Rebase ↓2 and Push")
        #expect(await model.publish())
        #expect(actions == ["rebase", "push"])
        #expect(model.canPublish == false)
    }
}
