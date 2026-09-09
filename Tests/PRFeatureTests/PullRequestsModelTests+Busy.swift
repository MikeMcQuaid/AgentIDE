@testable import PRFeature
import Testing

/// One branch action at a time: the other button dims while one
/// runs, since a push pressed mid-rebase failed.
extension PullRequestsModelTests {
    @Test
    func `no branch action is offered while one runs`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        model.fetchRebaseNeed = { _ in .sign }
        await model.reload()
        #expect(model.canPush)
        #expect(model.canRebase)

        model.isBranchActionRunning = true
        #expect(model.canPush == false)
        #expect(model.canRebase == false)
    }
}
