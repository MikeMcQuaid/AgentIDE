@testable import PRFeature
import Testing

extension PullRequestsModelTests {
    @Test
    func `typing settles before saving the latest draft`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.prTitle = "Saved title"
        model.saveDraft(defaults: ("Default title", "Default body"))
        let key = try #require(model.draftKey)
        let saved = try #require(model.store.load().pullRequestDrafts[key])

        model.prTitle = "Typing"
        model.prTitle = "Latest title"
        model.prBody = "Latest body"
        model.prTemplate = "Latest template"
        #expect(model.store.load().pullRequestDrafts[key] == saved)

        await model.draftSaveTask?.value
        let draft = try #require(model.store.load().pullRequestDrafts[key])
        #expect(draft.title == "Latest title")
        #expect(draft.body == "Latest body")
        #expect(draft.template == "Latest template")
        #expect(draft.defaultTitle == "Default title")
        #expect(draft.defaultBody == "Default body")
    }

    @Test
    func `cancelling an edit prevents its delayed draft from returning`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.selected = summary(1, head: "feature", body: "Existing body")
        model.beginEditing()
        let key = try #require(model.draftKey)
        model.prTitle = "Discard this title"
        let pending = model.draftSaveTask
        model.cancelEditing()

        await pending?.value
        #expect(model.store.load().pullRequestDrafts[key] == nil)
    }

    @Test
    func `switching branches preserves each pending draft under its own key`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let first = try #require(model.draftKey)
        model.prTitle = "First branch"
        await model.show(branch: "other")?.value
        let second = try #require(model.draftKey)
        model.prTitle = "Second branch"

        await model.draftSaveTask?.value
        #expect(first != second)
        #expect(model.store.load().pullRequestDrafts[first]?.title == "First branch")
        #expect(model.store.load().pullRequestDrafts[second]?.title == "Second branch")
    }

    @Test
    func `a reload cannot restore text cleared during the settling delay`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let key = try #require(model.draftKey)
        model.prTitle = "Old title"
        model.prBody = "Old body"
        model.flushDraft()

        model.prTitle = ""
        model.prBody = ""
        model.loadDraft()
        #expect(model.prTitle.isEmpty)
        #expect(model.prBody.isEmpty)
        #expect(model.store.load().pullRequestDrafts[key]?.title == "Old title")
        await model.draftSaveTask?.value
        #expect(model.store.load().pullRequestDrafts[key]?.title.isEmpty == true)
        #expect(model.store.load().pullRequestDrafts[key]?.body.isEmpty == true)
    }

    @Test
    func `a delayed save retains its key when the listed branch changes`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let key = try #require(model.draftKey)
        model.prTitle = "Original branch"
        model.stacking.selected = "another"

        await model.draftSaveTask?.value
        #expect(model.store.load().pullRequestDrafts[key]?.title == "Original branch")
        let another = try #require(model.draftKey)
        #expect(another != key)
        #expect(model.store.load().pullRequestDrafts[another] == nil)
    }
}
