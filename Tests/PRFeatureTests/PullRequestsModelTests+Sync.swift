import Foundation
@testable import PRFeature
import TerminalUI
import Testing

/// The pane and the sidebar share one summary cache and tell each
/// other when it changes.
extension PullRequestsModelTests {
    @Test
    func `rows repaint from what the sidebar cached, and a changed state bumps the bus`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.fetchList = { _, _ in [self.summary(7, head: "feature", checks: "PENDING")] }
        await model.reload()
        #expect(model.selected?.checks == "PENDING")

        // The sidebar's poll fetched fresher checks into the cache;
        // the next items update carries them into the pane.
        model.pullRequests.rememberSummary(
            repositoryPath: model.repository.path,
            summary: summary(7, head: "feature", checks: "SUCCESS"),
        )
        model.items = [item(branch: "feature", ahead: 0)]
        #expect(model.selected?.checks == "SUCCESS")
        #expect(model.summaries.first?.checks == "SUCCESS")

        let key = UtilityTabTarget.pullRequestCacheKey
        let before = UserDefaults.standard.integer(forKey: key)
        model.cacheEnriched(summary(7, head: "feature", checks: "SUCCESS"))
        #expect(UserDefaults.standard.integer(forKey: key) == before)
        model.cacheEnriched(summary(7, head: "feature", checks: "FAILURE"))
        #expect(UserDefaults.standard.integer(forKey: key) == before + 1)
    }
}
