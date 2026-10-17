import AgentIDEDomain
import SwiftUI

/// A repository header's branch picker, opened from its context
/// menu: a searchable list of origin's branches, any of which opens
/// as a new worktree. The list paints the branches already fetched,
/// then again after refreshing origin.
struct OpenBranchPopover: View {
    // MARK: Internal

    let repository: Repository
    let model: DashboardModel

    /// Told when a pick lands or the list is dismissed, so the
    /// popover closes.
    let onDone: () -> Void

    var body: some View {
        ReferencedItemSearchList(
            items: branches,
            selection: nil,
            searchPrompt: "Find a branch on origin by name",
            loadingTitle: "Listing origin's branches…",
            emptyTitle: "No other branches on origin",
            isLoading: isLoading,
            onPick: { open($0) },
            onClose: onDone,
        )
        .task { await reload() }
    }

    // MARK: Private

    @State private var branches: [RemoteBranch] = []
    /// Until the fetch answers, an empty list is not yet proven empty.
    @State private var isLoading = false

    private func reload() async {
        isLoading = true
        branches = await model.remoteBranches(repository: repository, fetching: false)
        let fresh = await model.remoteBranches(repository: repository, fetching: true)
        guard Task.isCancelled == false else {
            return
        }

        branches = fresh
        isLoading = false
    }

    private func open(_ branch: RemoteBranch) {
        onDone()
        Task { await model.openRemoteBranch(branch.name, in: repository) }
    }
}
