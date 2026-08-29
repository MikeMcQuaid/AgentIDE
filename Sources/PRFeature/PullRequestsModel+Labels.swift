/// The selected pull request's labels: read on selection, toggled
/// against GitHub. Split from the actions for length.
extension PullRequestsModel {
    /// The selected pull request's labels and, for the menu, the
    /// repository's; both read here since the Mine and Open scopes
    /// never read the worktree facts that carry the repository's.
    func loadSelectedLabels(_ number: Int) async {
        if availableLabels.isEmpty {
            availableLabels = await fetchLabels()
        }
        let labels = await fetchPullRequestLabels(number)
        if selected?.number == number {
            selectedLabels = labels
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
