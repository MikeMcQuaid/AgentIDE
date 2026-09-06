import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// Editing an open pull request's title and body in the form.
extension PullRequestsModelTests {
    @Test
    func `editing fills the form from the pull request and saves it back`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        await model.reload()
        let open = PullRequestSummary(
            number: 9,
            title: "Add the feature",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
            body: "What it did.",
        )
        model.summaries = [open]
        model.selected = open
        var saved = [(Int, String, String)]()
        model.performEdit = { number, title, body in saved.append((number, title, body)) }

        model.beginEditing()
        #expect(model.isEditing)
        #expect(model.prTitle == "Add the feature")
        #expect(model.prBody == "What it did.")

        // Bringing the description up to date with what was pushed.
        model.prTitle = "Add the feature and its tests"
        model.prBody = "What it did, and the tests that pin it."
        #expect(await model.saveEdits())
        #expect(saved.count == 1)
        #expect(saved.first?.1 == "Add the feature and its tests")
        #expect(saved.first?.2 == "What it did, and the tests that pin it.")
        // The pane and the row say the new words at once, and the
        // form is out of the way.
        #expect(model.selected?.title == "Add the feature and its tests")
        #expect(model.summaries.first?.body == "What it did, and the tests that pin it.")
        #expect(model.isEditing == false)
    }

    @Test
    func `cancelling an edit changes nothing, and a blank title cannot save`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        await model.reload()
        let open = PullRequestSummary(
            number: 9,
            title: "Add the feature",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
            body: "What it did.",
        )
        model.selected = open
        var saves = 0
        model.performEdit = { _, _, _ in saves += 1 }

        model.beginEditing()
        model.prTitle = ""
        #expect(await model.saveEdits() == false)
        #expect(saves == 0)

        model.prTitle = "Something else"
        model.cancelEditing()
        #expect(model.isEditing == false)
        #expect(model.selected?.title == "Add the feature")
        #expect(saves == 0)
    }
}
