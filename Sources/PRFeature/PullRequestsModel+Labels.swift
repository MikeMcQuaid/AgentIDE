/// The selected pull request's labels, which arrive with its
/// summary, toggled against GitHub. Split from the actions for
/// length.
extension PullRequestsModel {
    /// The repository's labels for the menu, read here since the
    /// Mine and Open scopes never read the worktree facts that carry
    /// them; the store answers from its cache for a day.
    func loadAvailableLabels() async {
        if availableLabels.isEmpty {
            availableLabels = await fetchLabels()
        }
    }

    /// Toggles one label on the selected pull request, optimistic
    /// so the chip answers the click; a refusal puts it back and
    /// reports. False opens the errors surface.
    func toggleLabel(_ label: String) async -> Bool {
        guard let number = selected?.number else {
            return false
        }

        let adding = selectedLabels.contains(label) == false
        let before = selectedLabels
        if adding {
            selectedLabels.append(label)
        } else {
            selectedLabels.removeAll { $0 == label }
        }
        do {
            try await performLabelChange(number, adding ? [label] : [], adding ? [] : [label])
            return true
        } catch {
            selectedLabels = before
            report("Changing labels on #" + String(number) + " failed: " + error.localizedDescription)
            return false
        }
    }
}
