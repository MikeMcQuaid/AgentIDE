@testable import PRFeature
import SanductorData
import SanductorDomain
import Synchronization
import Testing

extension PullRequestStackTests {
    @Test
    func `queued branches stop contributing preparation work immediately`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper"),
                outOfPlace: ["lower"],
                unpushed: ["lower", "upper"],
                unsigned: ["lower"],
            )
        }
        await model.reload()
        await model.show(branch: "upper")?.value
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("lower"),
            summaries: [fixtures.summary(1, head: "lower", base: "main")],
        )
        model.store.update { $0.queuedCache[model.repository.path] = [1] }

        #expect(model.canPublish)
        #expect(model.publishTitle == "Push")
        #expect(model.canRestack == false)
        #expect(model.needsRestackBeforePush == false)
        #expect(model.unpushedStackBranches == ["upper"])
        #expect(model.unpushedBelow == nil)
        model.store.update { $0.queuedCache[model.repository.path] = [] }
        #expect(model.canRestack)
        #expect(model.unpushedBelow == "lower")
    }

    @Test
    func `a queued branch disables preparation even with stale git facts`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        await model.reload()
        model.rebaseNeed = .rebaseAndSign
        model.tipSignature = .signed
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("feature"),
            summaries: [fixtures.summary(1, head: "feature", base: "main")],
        )
        model.store.update { $0.queuedCache[model.repository.path] = [1] }

        #expect(model.canPublish == false)
        #expect(model.canPush == false)
        #expect(model.canRebase == false)
        #expect(model.publishHelp.contains("queued"))
    }

    @Test(arguments: [false, true])
    func `the combined action pushes a ready or unsigned stack`(unsigned: Bool) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        let stack = BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        let actions = Mutex([String]())
        model.stacking.facts = { _ in
            StackFacts(
                stack: stack,
                unpushed: actions.withLock { $0.contains("push") } ? [] : ["lower"],
                unsigned: unsigned && actions.withLock { $0.isEmpty } ? ["lower"] : [],
            )
        }
        model.stacking.restack = { _, _ in
            actions.withLock { $0.append("rebase") }
            return ["lower", "upper"]
        }
        model.stacking.push = { worktree in
            #expect(worktree.branch == "lower")
            actions.withLock { $0.append("push") }
            return ["lower"]
        }
        await model.reload()
        #expect(model.canPublish)
        #expect(model.publishTitle == (unsigned ? "Sign and Push" : "Push"))
        #expect(await model.publish())
        #expect(actions.withLock { $0 } == (unsigned ? ["rebase", "push"] : ["push"]))
        #expect(model.isFullyPushed)
        #expect(model.canPublish == false)
        #expect(model.pushDoneTitle == "Pushed")
    }
}
