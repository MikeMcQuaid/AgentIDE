import AgentIDEDomain

/// Editing an open pull request's title and body in the creation
/// form: the same fields, the same drafting from the commits and the
/// same reset to them, saved with `gh pr edit` rather than opened.
/// What it is for is bringing a description up to date with what
/// was actually pushed before the pull request merges. Split from
/// the model body for length.
extension PullRequestsModel {
    /// Whether the form is editing the selected pull request.
    var isEditing: Bool {
        editingNumber != nil && editingNumber == selected?.number
    }

    /// Puts the selected pull request's title and body in the form.
    /// An edit left half done comes back: the form's draft is keyed
    /// by the pull request while it is edited, so it never touches
    /// the draft of a pull request yet to open.
    func beginEditing() {
        guard let selected, selected.state == "OPEN" else {
            return
        }

        editingNumber = selected.number
        loadingDraft = true
        prTitle = selected.title
        prBody = selected.body ?? ""
        loadingDraft = false
        loadDraft()
    }

    /// Leaves the edit without saving it, and forgets what was
    /// typed: cancelling is the one deliberate discard.
    func cancelEditing() {
        clearDraft()
        editingNumber = nil
    }

    /// Saves the form's title and body to the pull request; false
    /// opens the errors surface. The template is not appended, as
    /// it is when opening: the body already holds whatever of it
    /// the pull request was opened with.
    func saveEdits() async -> Bool {
        guard let selected, let number = editingNumber, number == selected.number else {
            return false
        }

        let title = prTitle.trimmingCharacters(in: .whitespaces)
        guard title.isEmpty == false else {
            report("the pull request needs a title")
            return false
        }

        isOpening = true
        defer { isOpening = false }
        do {
            try await performEdit(number, title, prBody)
            let edited = selected.retitled(title, body: prBody)
            cacheEnriched(edited)
            self.selected = edited
            if let index = summaries.firstIndex(where: { $0.number == number }) {
                summaries[index] = edited
            }
            note("edited `#" + String(number) + "`")
            cancelEditing()
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }
}
