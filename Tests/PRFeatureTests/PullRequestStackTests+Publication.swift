@testable import PRFeature
import SanductorData
import SanductorDomain
import Testing

extension PullRequestStackTests {
    @Test(arguments: ["lower", "middle", ""], ["push", "stack", "rebase"])
    func `publishing a later entry waits for every lower branch to be pushed`(
        missing: String,
        action: String,
    ) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        let stack = BranchStack(base: "main", branches: ["lower", "middle", "upper"], checkedOut: "upper")
        model.stacking.facts = { _ in
            StackFacts(stack: stack, outOfPlace: ["upper"], unpushed: [missing, "upper"].filter { $0.isEmpty == false })
        }
        var pushed = [String]()
        var rebased = false
        model.stacking.push = { worktree in
            pushed.append(worktree.branch)
            return [worktree.branch]
        }
        model.stacking.restack = { _, _ in
            rebased = true
            return ["upper"]
        }
        await model.reload()
        model.stacking.selected = "upper"

        #expect(model.canPushStack == missing.isEmpty)
        #expect(model.canPush == missing.isEmpty)
        if missing.isEmpty == false {
            #expect(model.pushStackHelp == "Push `" + missing + "` below this branch first")
        }
        switch action {
        case "push":
            _ = await model.push()

        case "stack":
            _ = await model.pushStack()

        default:
            #expect(await model.rebaseSigned())
        }
        #expect(pushed == (missing.isEmpty ? ["upper"] : []))
        #expect(rebased == (action == "rebase"))
    }

    @Test(arguments: ["lower", "middle", ""])
    func `opening a later entry waits for every lower pull request`(missing: String) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 0)])
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "middle", "upper"], checkedOut: "upper"))
        }
        var opened = [String]()
        model.performCreate = { worktree, _, _, _, _ in
            opened.append(worktree.branch)
            return "https://example.com/3"
        }
        await model.reload()
        model.stacking.selected = "upper"
        model.prTitle = "Upper work"
        for (index, branch) in ["lower", "middle"].enumerated() where branch != missing {
            model.pullRequests.rememberListing(
                repositoryPath: model.repository.path,
                scope: .branch(branch),
                summaries: [fixtures.summary(index + 1, head: branch)],
            )
        }

        #expect(model.unpushedBelow == nil)
        _ = await model.createPullRequest()
        #expect(opened == (missing.isEmpty ? ["upper"] : []))
    }
}
