import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

extension PullRequestStackTests {
    @Test(arguments: [false, true])
    func `published higher branches count towards push readiness without blocking publication`(unsigned: Bool) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(
                    base: "main",
                    branches: ["lower", "middle", "upper"],
                    checkedOut: "upper",
                    published: ["lower", "middle"],
                ),
                unpushed: ["middle", "upper"],
                unsigned: unsigned ? ["middle", "upper"] : ["upper"],
            )
        }
        await model.reload()
        model.stacking.selected = "lower"

        #expect(model.unpushedBelow == nil)
        #expect(model.unopenedBelow == nil)
        #expect(model.unpushedStackBranches == ["middle"])
        #expect(model.needsRestackBeforePush == unsigned)
        #expect(model.canPushStack == !unsigned)
        #expect(model.canPush == !unsigned)
        #expect(model.pushHelp == model.pushStackHelp)
        #expect(model.pushStackHelp.contains("not GPG signed") == unsigned)
    }

    @Test(arguments: ["push", "stack", "rebase"], ["lower", "middle"])
    func `stack actions push through the listed branch rather than the checked-out top`(
        action: String,
        branch: String,
    ) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "middle", "upper"], checkedOut: "upper"),
                outOfPlace: ["middle", "upper"],
                unpushed: branch == "lower" ? ["lower", "middle", "upper"] : ["middle", "upper"],
            )
        }
        model.stacking.restack = { _, _ in ["middle", "upper"] }
        var pushed = [String]()
        model.stacking.push = { worktree in
            pushed.append(worktree.branch)
            return branch == "lower" ? ["lower"] : ["lower", "middle"]
        }
        await model.reload()
        model.stacking.selected = branch

        switch action {
        case "push":
            #expect(await model.push())

        case "stack":
            #expect(await model.pushStack())

        default:
            #expect(await model.rebaseSigned())
        }
        #expect(pushed == [branch])
    }

    @Test
    func `unpushed and unsigned higher branches do not affect the listed push`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        let stack = BranchStack(base: "main", branches: ["lower", "middle", "upper"], checkedOut: "upper")
        model.stacking.facts = { _ in StackFacts(stack: stack, unpushed: ["middle", "upper"]) }
        await model.reload()
        model.stacking.selected = "lower"
        #expect(model.canPushStack == false)
        #expect(model.unpushedStackBranches.isEmpty)

        model.stacking.facts = { _ in
            StackFacts(stack: stack, unpushed: ["middle", "upper"], unsigned: ["upper"])
        }
        await model.loadStack()
        model.stacking.selected = "middle"
        #expect(model.canPushStack)
        #expect(model.canRestack)
        #expect(model.needsRestackBeforePush == false)
        #expect(model.unpushedStackBranches == ["middle"])
        #expect(model.pushStackHelp.contains("not GPG signed") == false)
        model.stacking.unpushedBranches = ["upper"]
        model.stacking.selected = "upper"
        #expect(model.canPushStack == false)
        #expect(model.needsRestackBeforePush)
        #expect(model.pushStackHelp.contains("not GPG signed"))
    }
}
