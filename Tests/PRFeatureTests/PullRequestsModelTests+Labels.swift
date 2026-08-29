import Foundation
@testable import PRFeature
import Testing

/// Labels on an open pull request: read on selection, toggled
/// optimistically and put back when GitHub refuses.
extension PullRequestsModelTests {
    @Test
    @MainActor
    func `toggling a label on an open pull request edits it on GitHub`() async {
        let model = makeModel()
        model.fetchPullRequestLabels = { _ in ["bug"] }
        model.fetchLabels = { ["bug", "ci"] }
        var added = [[String]]()
        var removed = [[String]]()
        model.performLabelChange = { _, add, remove in
            added.append(add)
            removed.append(remove)
        }
        model.select(summary(4, head: "feature"))
        await model.loadSelectedLabels(4)
        #expect(model.selectedLabels == ["bug"])
        #expect(model.availableLabels == ["bug", "ci"])

        #expect(await model.toggleLabel("ci"))
        #expect(await model.toggleLabel("bug"))
        #expect(model.selectedLabels == ["ci"])
        #expect(added == [["ci"], []])
        #expect(removed == [[], ["bug"]])

        model.performLabelChange = { _, _, _ in throw CancellationError() }
        #expect(await model.toggleLabel("bug") == false)
        #expect(model.selectedLabels == ["ci"])
    }
}
