import AgentIDEData
import AgentIDEDomain

/// The creation form's draft persistence and template helpers, split
/// from the model body for length: a branch's unfinished title, body
/// and template survive leaving the tab and quitting the app.
extension PullRequestsModel {
    /// The worktree this tab is for. Found by path first: a
    /// worktree's branch changes under the app whenever an agent or
    /// a restack checks another one out, and matching on the name
    /// the sidebar last cached then found nothing at all, which
    /// took the footer's actions and the whole stack with it.
    var branchItem: WorktreeItem? {
        items.first { $0.worktree.path == worktreePath }
            ?? items.first { $0.worktree.branch == branch }
            ?? items.first { $0.worktree.branch == currentBranch }
    }

    /// Whether the list pane shows the creation form instead: the
    /// worktree scope with no open pull request for the branch.
    var needsCreateForm: Bool {
        scope == .worktree && branchItem != nil && hasLoaded
            && summaries.contains { $0.headBranch == listedBranch && $0.state == "OPEN" } == false
    }

    /// Whether the last fetch filled its limit, so more pages may
    /// exist beyond what is loaded.
    var hasMore: Bool {
        summaries.isEmpty == false && summaries.count == fetchedLimit
    }

    /// Paints the stored listing for this scope, if any. A cached
    /// listing decides the creation form as surely as a fetched one,
    /// so returning to the tab shows it instantly rather than a
    /// loading state.
    func paintCachedListing() {
        guard let cached = pullRequests.cachedListing(
            repositoryPath: repository.path,
            scope: scope.listScope(branch: listedBranch),
        ) else {
            summaries = []
            return
        }

        summaries = cached
        hasLoaded = true
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
    /// one thing every template review does by hand. A ticked AI
    /// box claims a disclosure below it, so one is written: ticking
    /// that box and leaving the section empty would be the one lie
    /// this button could tell.
    func tickTemplateBoxes() {
        prTemplate = prTemplate
            .replacing("- [ ]", with: "- [x]")
            .replacing("* [ ]", with: "* [x]")
        discloseInTemplate()
    }

    /// Saves the drafted title, body and template for this branch as
    /// they change; the model itself is rebuilt whenever the branch
    /// changes, which is what used to lose the writing.
    func saveDraft() {
        guard loadingDraft == false, let key = draftKey else {
            return
        }

        store.update { metadata in
            metadata.pullRequestDrafts[key] = PullRequestFormDraft(
                title: prTitle,
                body: prBody,
                template: prTemplate,
            )
        }
    }

    /// Restores a saved draft into whatever is still empty. Only
    /// empty fields are filled, so a reload, which push and rebase
    /// both trigger, can never overwrite what is being typed: the
    /// draft is a fallback for a fresh model, not the truth about a
    /// live one. Title, body and template each answer for
    /// themselves, since they are edited separately.
    func loadDraft() {
        guard let key = draftKey, let draft = store.load().pullRequestDrafts[key] else {
            return
        }

        loadingDraft = true
        if Self.isBlank(prTitle) {
            prTitle = draft.title
        }
        if Self.isBlank(prBody) {
            prBody = draft.body
        }
        if Self.isBlank(prTemplate) {
            prTemplate = draft.template
        }
        loadingDraft = false
        // What was already typed may be newer than the draft, so the
        // draft is brought back up to date rather than left behind.
        saveDraft()
    }

    /// Forgets a branch's draft once its pull request exists.
    func clearDraft() {
        guard let key = draftKey else {
            return
        }

        store.update { metadata in
            metadata.pullRequestDrafts.removeValue(forKey: key)
        }
        loadingDraft = true
        prTitle = ""
        prBody = ""
        prTemplate = ""
        loadingDraft = false
    }
}
