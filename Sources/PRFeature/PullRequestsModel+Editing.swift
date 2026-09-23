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

    /// Whether the edit shows the template apart from the body,
    /// which it does when the body was opened with the repository's
    /// template: the boxes and sections are then edited where they
    /// were filled in, not as a block of markdown under the words.
    var editsTemplate: Bool {
        isEditing && editingSplitsTemplate
    }

    /// Puts the selected pull request's title and body in the form,
    /// the template apart when the body holds it. An edit left half
    /// done comes back: the form's draft is keyed by the pull request
    /// while it is edited, so it never touches the draft of a pull
    /// request yet to open.
    func beginEditing() {
        guard let selected, selected.state == "OPEN" else {
            return
        }

        editingNumber = selected.number
        loadingDraft = true
        prTitle = selected.title
        let split = hasTemplate ? Self.splitTemplate(from: selected.body ?? "", template: originalTemplate) : nil
        editingSplitsTemplate = split != nil
        prBody = split?.body ?? selected.body ?? ""
        prTemplate = split?.template ?? ""
        loadingDraft = false
        loadDraft()
    }

    /// Leaves the edit without saving it, and forgets what was
    /// typed: cancelling is the one deliberate discard.
    func cancelEditing() {
        clearDraft()
        editingNumber = nil
        editingSplitsTemplate = false
    }

    /// The body as it was opened, taken apart again: what was
    /// written, then the template after an empty line. The template
    /// is found by its first line, since ticking its boxes and
    /// filling its sections leaves the rest of it changed, at the
    /// last place that line opens a line: the template was appended
    /// after the words, so a description using the same heading
    /// itself keeps it. A body without that line is all body.
    static func splitTemplate(from body: String, template: String) -> (body: String, template: String)? {
        let lines = template.split(whereSeparator: \.isNewline).map(String.init)
        guard let marker = lines.first(where: { isBlank($0) == false }),
              let start = body.ranges(of: marker)
              .last(where: { range in
                  range.lowerBound == body.startIndex || body[body.index(before: range.lowerBound)].isNewline
              })?.lowerBound
        else {
            return nil
        }

        let written = body[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        return (written, String(body[start...]))
    }

    /// The body and the template as GitHub gets them: the template
    /// after an empty line, or the body alone when there is none.
    static func joined(body: String, template: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return body + (trimmed.isEmpty ? "" : "\n\n" + trimmed)
    }

    /// Saves the form's title and body to the pull request; false
    /// opens the errors surface. The template goes back under the
    /// body when the edit took it apart; otherwise the body already
    /// holds whatever of it the pull request was opened with.
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
        let body = editingSplitsTemplate ? Self.joined(body: prBody, template: prTemplate) : prBody
        do {
            try await performEdit(number, title, body)
            let edited = selected.retitled(title, body: body)
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
