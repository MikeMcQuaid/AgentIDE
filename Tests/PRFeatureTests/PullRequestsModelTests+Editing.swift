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
    func `a body opened with the template is edited in two fields and saved as one`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        await model.reload()
        model.hasTemplate = true
        model.originalTemplate = "## Checklist\n- [ ] Tests"
        model.selected = summary(9, head: "feature", body: "What it did.\n\n## Checklist\n- [x] Tests")
        var saved = [String]()
        model.performEdit = { _, _, body in saved.append(body) }

        // The template is found by its first line, boxes ticked and
        // all, and edited where it was filled in.
        model.beginEditing()
        #expect(model.editsTemplate)
        #expect(model.prBody == "What it did.")
        #expect(model.prTemplate == "## Checklist\n- [x] Tests")

        model.prBody = "What it did, in full."
        model.prTemplate = "## Checklist\n- [x] Tests\n- [x] Docs"
        #expect(await model.saveEdits())
        #expect(saved == ["What it did, in full.\n\n## Checklist\n- [x] Tests\n- [x] Docs"])

        // A description using the template's own heading keeps it:
        // the template was appended last, so the last such line is
        // where it starts.
        model.selected = summary(11, head: "feature", body: "## Checklist\nMine.\n\n## Checklist\n- [x] Tests")
        model.beginEditing()
        #expect(model.prBody == "## Checklist\nMine.")
        #expect(model.prTemplate == "## Checklist\n- [x] Tests")
        model.cancelEditing()

        // A body opened without the template is all body, and saves
        // as it reads.
        model.selected = summary(10, head: "feature", body: "Just words.")
        model.beginEditing()
        #expect(model.editsTemplate == false)
        #expect(model.prBody == "Just words.")
        #expect(model.prTemplate.isEmpty)
        #expect(await model.saveEdits())
        #expect(saved.last == "Just words.")
    }

    @Test(arguments: ["<!-- Only tick a checkbox once you've done it. -->", "- [ ] Tests", "* [ ] Tests"])
    func `a repeated template separator keeps the checklist and disclosure together`(opening: String) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        await model.reload()
        model.hasTemplate = true
        model.originalTemplate = """
        -----

        \(opening)

        - [ ] Have you followed our Contributing guidelines?

        -----

        - [ ] I did not use AI/LLM to create this PR, or I disclosed the tool/model below.

        <!-- If AI was used, explain below how it was used and how you verified the changes. -->

        -----
        """
        let filled = model.originalTemplate.replacing("[ ]", with: "[x]")
        let description = "What it did.\n\n-----\n\nWhy it changed."
        let body = description + "\n\n" + filled
        model.selected = summary(9, head: "feature", body: body)
        var saved: String?
        model.performEdit = { _, _, body in saved = body }

        model.beginEditing()
        #expect(model.editsTemplate)
        #expect(model.prBody == description)
        #expect(model.prTemplate == filled)
        #expect(await model.saveEdits())
        #expect(saved == body)

        model.selected = summary(10, head: "feature", body: description)
        model.beginEditing()
        #expect(model.editsTemplate == false)
        #expect(model.prBody == description)
        #expect(model.prTemplate.isEmpty)
    }

    @Test
    func `a template opening must match a whole line`() {
        #expect(PullRequestsModel.splitTemplate(
            from: "Description.\n\n## Checklist notes\nMy own notes.",
            template: "## Checklist\n- [ ] Tests",
        ) == nil)
    }

    @Test(arguments: ["Verified the changes.", "Describe the changes."])
    func `an edited first section keeps the whole template apart`(verification: String) throws {
        let template = "-----\n\nDescribe the changes.\n\n-----\n\nDescribe the verification.\n\n-----"
        let filled = "-----\n\nUpdated the page copy.\n\n-----\n\n" + verification + "\n\n-----"
        let description = "What it did.\n\n-----\n\nWhy it changed."
        let body = description + "\n\n" + filled
        let split = try #require(PullRequestsModel.splitTemplate(from: body, template: template))

        #expect(split.body == description)
        #expect(split.template == filled)
        #expect(PullRequestsModel.joined(body: split.body, template: split.template) == body)
        #expect(PullRequestsModel.splitTemplate(from: description + "\n\n-----", template: template) == nil)
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
