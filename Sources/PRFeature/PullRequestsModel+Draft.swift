import AgentIDEData
import AgentIDEDomain

/// The creation form's draft persistence and template helpers, split
/// from the model body for length: a branch's unfinished title, body
/// and template survive leaving the tab and quitting the app.
extension PullRequestsModel {
    /// Whether the last fetch filled its limit, so more pages may
    /// exist beyond what is loaded.
    var hasMore: Bool {
        summaries.isEmpty == false && summaries.count == fetchedLimit
    }

    /// Where a branch's draft is stored, nil without a branch.
    var draftKey: String? {
        listedBranch.map { repository.path + "#" + $0 }
    }

    /// Whether the template still reads as the repository's own: a
    /// pull request opened with its placeholders intact helps nobody,
    /// so Open PR waits for it to be filled in.
    var templateUnedited: Bool {
        hasTemplate && prTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            == originalTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ticks every unticked markdown checkbox in the template, the
    /// one thing every template review does by hand.
    func tickTemplateBoxes() {
        prTemplate = prTemplate
            .replacing("- [ ]", with: "- [x]")
            .replacing("* [ ]", with: "* [x]")
    }

    /// Saves the drafted title, body and template for this branch as
    /// they change; the model itself is rebuilt whenever the branch
    /// changes, which is what used to lose the writing.
    func saveDraft() {
        guard loadingDraft == false, let key = draftKey else {
            return
        }

        var metadata = store.load()
        metadata.pullRequestDrafts[key] = PullRequestFormDraft(
            title: prTitle,
            body: prBody,
            template: prTemplate,
        )
        store.save(metadata)
    }

    /// Restores a saved draft, if any; reload calls this before the
    /// template is fetched, so typed text always wins over it.
    func loadDraft() {
        guard let key = draftKey, let draft = store.load().pullRequestDrafts[key] else {
            return
        }

        loadingDraft = true
        prTitle = draft.title
        prBody = draft.body
        prTemplate = draft.template
        loadingDraft = false
    }

    /// Forgets a branch's draft once its pull request exists.
    func clearDraft() {
        guard let key = draftKey else {
            return
        }

        var metadata = store.load()
        metadata.pullRequestDrafts.removeValue(forKey: key)
        store.save(metadata)
        loadingDraft = true
        prTitle = ""
        prBody = ""
        prTemplate = ""
        loadingDraft = false
    }
}
