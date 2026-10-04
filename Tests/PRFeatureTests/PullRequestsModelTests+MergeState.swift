import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [false, true], [false, true])
    func `the merge button shows enabled automerge separately from queueing`(queue: Bool, stacked: Bool) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        if stacked {
            model.fetchCurrentBranch = { _ in "upper" }
            model.stacking.facts = { _ in
                StackFacts(stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper"))
            }
            await model.reload()
        }
        for queued in [false, true] {
            model.hasMergeQueue = queue
            model.selected = PullRequestSummary(
                number: 7,
                title: "Waiting",
                url: "",
                headBranch: "upper",
                mergeable: "UNKNOWN",
                reviewDecision: "REVIEW_REQUIRED",
                checks: "PENDING",
                hasAutomerge: true,
                isQueued: queued,
            )
            #expect(model.mergeActionTitle == (queued ? "Queued" : "Automerge"))
            #expect(model.canMergeAction)
            #expect(model.mergeActionBusyTitle == (queued ? "Dequeuing" : "Disabling"))
            var action = ""
            model.performMergeChange = { _ in action = "cancel"; return nil }
            model.performMergeStack = { _, _ in action = "merge"; return .pending }
            #expect(await model.performMergeAction())
            #expect(action == "cancel")
        }
    }

    @Test
    func `a waiting stack explains why automerge is unavailable`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper"))
        }
        await model.reload()
        model.selected = summary(7, head: "upper", base: "lower", mergeable: "MERGEABLE", checks: "PENDING")
        #expect(model.isInStack)
        #expect(model.mergeActionTitle == "Waiting")
        #expect(model.canMergeAction == false)
        #expect(model.mergeActionHelp.contains("GitHub does not support automerge for stacked pull requests"))
        var submitted = false
        model.performMergeChange = { _ in submitted = true; return nil }
        model.performMergeStack = { _, _ in submitted = true; return .pending }
        await model.performMergeAction()
        #expect(submitted == false)
    }

    @Test
    func `the merge button reads queue membership from the shared cache`() {
        let model = makeModel()
        model.store.update { $0.queuedCache["/repo"] = [7] }
        model.selected = model.withCachedUnresolved(summary(7, head: "feature"))
        #expect(model.mergeActionTitle == "Queued")
    }

    @Test
    func `a draft in a stack is marked ready without merging`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper"))
        }
        await model.reload()
        model.selected = PullRequestSummary(
            number: 7,
            title: "Draft",
            url: "",
            headBranch: "upper",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            isDraft: true,
        )
        #expect(model.isInStack)
        #expect(model.mergeActionTitle == "Ready")
        #expect(model.canMergeAction)
        var action = ""
        model.performMergeChange = { _ in action = "ready"; return nil }
        model.performMergeStack = { _, _ in action = "merge"; return .pending }
        #expect(await model.performMergeAction())
        #expect(action == "ready")
    }
}
