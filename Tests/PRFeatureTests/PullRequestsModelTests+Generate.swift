import Foundation
@testable import PRFeature
import Testing

/// Drafting the form from the commits, split from the model tests
/// for length.
extension PullRequestsModelTests {
    @Test
    func `generating fills blank fields and completes the template`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchCommitMessages = { _, _ in ["First change\n\nWhy one.", "Second change"] }
        var draftedFor = ""
        model.generateDescription = { _, branch in
            draftedFor = branch
            return ("Drafted title", "Drafted body")
        }
        model.fillTemplate = { _, template in "filled: " + template }
        model.prTemplate = "- [ ] Checked"
        #expect(await model.generateDescription())
        #expect(draftedFor == "feature")
        #expect(model.prTitle == "Drafted title")
        #expect(model.prBody == "Drafted body")
        #expect(model.prTemplate == "filled: - [ ] Checked")

        // Typed text stays unless the form asked and was told to
        // replace it.
        model.prTitle = "Typed"
        model.generateDescription = { _, _ in ("Again", "Again body") }
        #expect(await model.generateDescription())
        #expect(model.prTitle == "Typed")
        #expect(await model.generateDescription(replacing: true))
        #expect(model.prTitle == "Again")

        // Without a repository template nothing is invented.
        let bare = makeModel(items: [item(branch: "feature", ahead: 1)])
        bare.fetchCommitMessages = { _, _ in ["Only change\n\nWhy."] }
        bare.fillTemplate = { _, _ in "should never be asked" }
        #expect(await bare.generateDescription())
        #expect(bare.prTitle == "Only change")
        #expect(bare.prBody == "Why.")
        #expect(bare.prTemplate.isEmpty)
    }
}
