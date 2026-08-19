import AgentIDEData
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
        // The footer and the messages pane both say where it went,
        // since pushing somewhere other than the repository you are
        // looking at is worth knowing.
        #expect(model.status == "Pushed.")

        // A branch in a fork names itself for the pull request; one
        // in the repository does not.
        #expect(PushDestination.fork(owner: "MikeMcQuaid").head(branch: "feature") == "MikeMcQuaid:feature")
        #expect(PushDestination.origin.head(branch: "feature") == nil)
    }
}
